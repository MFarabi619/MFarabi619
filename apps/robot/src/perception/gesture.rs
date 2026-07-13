use std::{
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Instant,
};

use foxglove::messages::{
    points_annotation, Color, ImageAnnotations, Point2, PointsAnnotation, TextAnnotation,
};
use oxidros::{
    msg::common_interfaces::{geometry_msgs::msg::Twist, sensor_msgs::msg::CompressedImage},
    prelude::*,
};

use super::{
    onnx::OnnxModel,
    palm::{decode_rgb, Config as PalmConfig, Detector as PalmDetector, Hand, RGB_CHANNELS},
    twist, WATCHDOG_TIMEOUT,
};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const LANDMARK_INPUT: usize = 224;
const LANDMARK_COUNT: usize = 21;
const PRESENCE_THRESHOLD: f32 = 0.6;
const HANDEDNESS_MARGIN: f32 = 0.05;
const LOG_STRIDE_FRAMES: u64 = 10;
const CROP_EXPANSION: f64 = 2.7;
const FINGER_OPEN_ANGLE_RAD: f32 = 2.8;
const THUMB_OPEN_ANGLE_RAD: f32 = 2.4;
const GESTURE_LABEL_SIZE: f64 = 28.0;
const DEBOUNCE_FRAMES: usize = 4;
const FORWARD_SPEED: f64 = 0.4;
const TURN_SPEED: f64 = 0.8;
const SLEW_LINEAR: f64 = 0.05;
const SLEW_ANGULAR: f64 = 0.1;

// MediaPipe hand landmark connections (0=wrist; thumb 1-4; index 5-8; middle 9-12; ring 13-16; pinky 17-20).
const HAND_CONNECTIONS: [(usize, usize); 21] = [
    (0, 1),
    (1, 2),
    (2, 3),
    (3, 4),
    (0, 5),
    (5, 6),
    (6, 7),
    (7, 8),
    (5, 9),
    (9, 10),
    (10, 11),
    (11, 12),
    (9, 13),
    (13, 14),
    (14, 15),
    (15, 16),
    (13, 17),
    (17, 18),
    (18, 19),
    (19, 20),
    (0, 17),
];

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Gesture {
    None,
    OpenPalm,
    ThumbUp,
    Point,
    Fist,
    Victory,
}

fn default_landmark_model() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets/hand_landmarks.onnx")
}

struct CropRect {
    center_x: f64,
    center_y: f64,
    side: f64,
    rotation: f64,
}

fn palm_crop_rect(hand: &Hand, width: usize, height: usize) -> CropRect {
    let frame_width = width as f64;
    let frame_height = height as f64;
    let side = (hand.width * frame_width).max(hand.height * frame_height) * CROP_EXPANSION;
    CropRect {
        center_x: hand.center_x * frame_width,
        center_y: hand.center_y * frame_height,
        side,
        rotation: hand.rotation,
    }
}

// Map a crop-normalized point (0..1 per axis) to source-image pixels, rotating about the
// crop center. Shared by the sampler and the overlay back-projection so they can't disagree.
fn crop_to_image(rect: &CropRect, normalized_x: f64, normalized_y: f64) -> (f64, f64) {
    let (sin, cos) = rect.rotation.sin_cos();
    let u = (normalized_x - 0.5) * rect.side;
    let v = (normalized_y - 0.5) * rect.side;
    (
        rect.center_x + u * cos - v * sin,
        rect.center_y + u * sin + v * cos,
    )
}

fn preprocess_crop(rgb: &[u8], width: usize, height: usize, rect: &CropRect) -> Vec<f32> {
    let mut input = vec![0.0f32; LANDMARK_INPUT * LANDMARK_INPUT * RGB_CHANNELS];
    for y in 0..LANDMARK_INPUT {
        let normalized_y = (y as f64 + 0.5) / LANDMARK_INPUT as f64;
        for x in 0..LANDMARK_INPUT {
            let normalized_x = (x as f64 + 0.5) / LANDMARK_INPUT as f64;
            let (source_x, source_y) = crop_to_image(rect, normalized_x, normalized_y);
            let (source_x, source_y) = (source_x as isize, source_y as isize);
            if source_x < 0
                || source_x >= width as isize
                || source_y < 0
                || source_y >= height as isize
            {
                continue;
            }
            let source = (source_y as usize * width + source_x as usize) * RGB_CHANNELS;
            let destination = (y * LANDMARK_INPUT + x) * RGB_CHANNELS;
            input[destination] = rgb[source] as f32 / 255.0;
            input[destination + 1] = rgb[source + 1] as f32 / 255.0;
            input[destination + 2] = rgb[source + 2] as f32 / 255.0;
        }
    }
    input
}

// MediaPipe's handedness head is a sigmoid: a real hand reads confidently left/right
// (near 0 or 1), a non-hand (e.g. a bare foot) drifts to the ambiguous ~0.5 middle.
fn handedness_is_confident(handedness: f32) -> bool {
    (handedness - 0.5).abs() >= HANDEDNESS_MARGIN
}

struct LandmarkDetector {
    model: OnnxModel,
    frames: AtomicU64,
}

impl LandmarkDetector {
    fn load(model_path: &Path) -> Result<Self, BoxError> {
        Ok(Self {
            model: OnnxModel::load(model_path)?,
            frames: AtomicU64::new(0),
        })
    }

    // 21 landmarks in crop-normalized (0..1) coords, or None when the crop isn't a confident hand.
    fn detect(
        &self,
        rgb: &[u8],
        width: usize,
        height: usize,
        rect: &CropRect,
    ) -> Option<[[f32; 3]; LANDMARK_COUNT]> {
        let outputs = self
            .model
            .run(
                &preprocess_crop(rgb, width, height, rect),
                &[1, LANDMARK_INPUT, LANDMARK_INPUT, RGB_CHANNELS],
            )
            .ok()?;
        let landmarks = &outputs[0].data;
        let presence = *outputs.get(1)?.data.first()?;
        let handedness = *outputs.get(2)?.data.first()?;
        if self
            .frames
            .fetch_add(1, Ordering::Relaxed)
            .is_multiple_of(LOG_STRIDE_FRAMES)
        {
            tracing::debug!("hand candidate presence={presence:.2} handedness={handedness:.2}");
        }
        if presence < PRESENCE_THRESHOLD || !handedness_is_confident(handedness) {
            return None;
        }

        let side = LANDMARK_INPUT as f32;
        let mut points = [[0.0f32; 3]; LANDMARK_COUNT];
        for (index, point) in points.iter_mut().enumerate() {
            let base = index * 3;
            *point = [
                landmarks[base] / side,
                landmarks[base + 1] / side,
                landmarks[base + 2] / side,
            ];
        }
        Some(points)
    }
}

// MediaPipe hand-landmark indices per finger: (metacarpal, proximal joint, tip).
struct Finger {
    metacarpal: usize,
    proximal: usize,
    tip: usize,
}

const THUMB: Finger = Finger {
    metacarpal: 2,
    proximal: 3,
    tip: 4,
};
const INDEX_FINGER: Finger = Finger {
    metacarpal: 5,
    proximal: 6,
    tip: 8,
};
const MIDDLE_FINGER: Finger = Finger {
    metacarpal: 9,
    proximal: 10,
    tip: 12,
};
const RING_FINGER: Finger = Finger {
    metacarpal: 13,
    proximal: 14,
    tip: 16,
};
const PINKY_FINGER: Finger = Finger {
    metacarpal: 17,
    proximal: 18,
    tip: 20,
};

fn finger_is_open(
    landmarks: &[[f32; 3]; LANDMARK_COUNT],
    finger: &Finger,
    open_angle: f32,
) -> bool {
    let toward_base = (
        landmarks[finger.metacarpal][0] - landmarks[finger.proximal][0],
        landmarks[finger.metacarpal][1] - landmarks[finger.proximal][1],
    );
    let toward_tip = (
        landmarks[finger.tip][0] - landmarks[finger.proximal][0],
        landmarks[finger.tip][1] - landmarks[finger.proximal][1],
    );
    let dot = toward_base.0 * toward_tip.0 + toward_base.1 * toward_tip.1;
    let base_length = toward_base.0.hypot(toward_base.1);
    let tip_length = toward_tip.0.hypot(toward_tip.1);
    if base_length == 0.0 || tip_length == 0.0 {
        return false;
    }
    let angle = (dot / (base_length * tip_length)).clamp(-1.0, 1.0).acos();
    angle > open_angle
}

pub fn classify_gesture(landmarks: &[[f32; 3]; LANDMARK_COUNT]) -> Gesture {
    let thumb = finger_is_open(landmarks, &THUMB, THUMB_OPEN_ANGLE_RAD);
    let index = finger_is_open(landmarks, &INDEX_FINGER, FINGER_OPEN_ANGLE_RAD);
    let middle = finger_is_open(landmarks, &MIDDLE_FINGER, FINGER_OPEN_ANGLE_RAD);
    let ring = finger_is_open(landmarks, &RING_FINGER, FINGER_OPEN_ANGLE_RAD);
    let pinky = finger_is_open(landmarks, &PINKY_FINGER, FINGER_OPEN_ANGLE_RAD);
    match (thumb, index, middle, ring, pinky) {
        (_, true, true, true, true) => Gesture::OpenPalm,
        (true, false, false, false, false) => Gesture::ThumbUp,
        (false, false, false, false, false) => Gesture::Fist,
        (_, true, false, false, false) => Gesture::Point,
        (_, true, true, false, false) => Gesture::Victory,
        _ => Gesture::None,
    }
}

fn skeleton_color() -> Color {
    Color {
        r: 0.0,
        g: 1.0,
        b: 0.4,
        a: 1.0,
    }
}

fn skeleton_annotations(
    landmarks: &[[f32; 3]; LANDMARK_COUNT],
    rect: &CropRect,
    gesture: Gesture,
) -> ImageAnnotations {
    let to_pixel = |landmark: &[f32; 3]| {
        let (x, y) = crop_to_image(rect, landmark[0] as f64, landmark[1] as f64);
        Point2 { x, y }
    };
    let landmark_points: Vec<Point2> = landmarks.iter().map(to_pixel).collect();
    let mut connection_lines = Vec::with_capacity(HAND_CONNECTIONS.len() * 2);
    for (from, to) in HAND_CONNECTIONS {
        connection_lines.push(landmark_points[from]);
        connection_lines.push(landmark_points[to]);
    }

    let mut annotations = ImageAnnotations::default();
    annotations.points.push(PointsAnnotation {
        r#type: points_annotation::Type::LineList as i32,
        points: connection_lines,
        outline_color: Some(skeleton_color()),
        thickness: 2.0,
        ..Default::default()
    });
    annotations.points.push(PointsAnnotation {
        r#type: points_annotation::Type::Points as i32,
        points: landmark_points,
        outline_color: Some(skeleton_color()),
        thickness: 5.0,
        ..Default::default()
    });
    annotations.texts.push(TextAnnotation {
        position: Some(Point2 {
            x: (rect.center_x - rect.side / 2.0).max(0.0),
            y: (rect.center_y - rect.side / 2.0).max(GESTURE_LABEL_SIZE),
        }),
        text: format!("{gesture:?}"),
        font_size: GESTURE_LABEL_SIZE,
        text_color: Some(skeleton_color()),
        background_color: Some(Color {
            r: 0.0,
            g: 0.0,
            b: 0.0,
            a: 0.6,
        }),
        ..Default::default()
    });
    annotations
}

fn behavior_velocity(gesture: Gesture) -> (f64, f64) {
    match gesture {
        Gesture::ThumbUp => (FORWARD_SPEED, 0.0),
        Gesture::Fist => (-FORWARD_SPEED, 0.0),
        Gesture::Point => (0.0, TURN_SPEED),
        Gesture::Victory => (0.0, -TURN_SPEED),
        Gesture::OpenPalm | Gesture::None => (0.0, 0.0),
    }
}

fn slew(current: f64, target: f64, max_step: f64) -> f64 {
    current + (target - current).clamp(-max_step, max_step)
}

struct PetBrain {
    committed: Gesture,
    candidate: Gesture,
    candidate_frames: usize,
    linear: f64,
    angular: f64,
}

impl PetBrain {
    fn new() -> Self {
        Self {
            committed: Gesture::None,
            candidate: Gesture::None,
            candidate_frames: 0,
            linear: 0.0,
            angular: 0.0,
        }
    }

    fn committed(&self) -> Gesture {
        self.committed
    }

    fn velocity(&self) -> (f64, f64) {
        (self.linear, self.angular)
    }

    fn update(&mut self, gesture: Gesture) {
        if gesture == self.candidate {
            self.candidate_frames += 1;
        } else {
            self.candidate = gesture;
            self.candidate_frames = 1;
        }
        if self.candidate_frames >= DEBOUNCE_FRAMES {
            self.committed = self.candidate;
        }
        let (target_linear, target_angular) = behavior_velocity(self.committed);
        self.linear = slew(self.linear, target_linear, SLEW_LINEAR);
        self.angular = slew(self.angular, target_angular, SLEW_ANGULAR);
    }

    fn halt(&mut self) {
        *self = Self::new();
    }
}

pub async fn run_gesture_pet(node: Arc<Node>) -> Result<(), BoxError> {
    let palm_config = PalmConfig::default();
    let palm = PalmDetector::load(&palm_config)?;
    let landmarker = LandmarkDetector::load(&default_landmark_model())?;
    let mut images =
        node.create_subscriber::<CompressedImage>("image", Some(crate::qos::sensor_data()))?;
    let cmd_vel = node.create_publisher::<Twist>("cmd_vel", Some(crate::qos::command()))?;
    let skeleton = foxglove::ChannelBuilder::new("/hand/landmarks").build::<ImageAnnotations>();
    let mut brain = PetBrain::new();
    let mut last_committed = brain.committed();

    tracing::info!(
        "gesture pet reading {} -> cmd_vel",
        images.fully_qualified_topic_name()
    );
    let ctrl_c = tokio::signal::ctrl_c();
    tokio::pin!(ctrl_c);
    let mut watchdog = tokio::time::interval(WATCHDOG_TIMEOUT);
    let mut last_frame = Instant::now();
    loop {
        tokio::select! {
            _ = &mut ctrl_c => break,
            _ = watchdog.tick() => {
                if last_frame.elapsed() >= WATCHDOG_TIMEOUT {
                    brain.halt();
                    let (linear, angular) = brain.velocity();
                    cmd_vel.send(&twist(linear, angular))?;
                    skeleton.log(&ImageAnnotations::default());
                }
            }
            message = images.recv() => {
                last_frame = Instant::now();
                let gesture = match decode_rgb(message?.sample.data.as_slice()) {
                    Err(error) => {
                        tracing::warn!("{error}");
                        continue;
                    }
                    Ok((rgb, width, height)) => match palm.best_hand(&rgb, width, height, palm_config.min_score) {
                        None => {
                            skeleton.log(&ImageAnnotations::default());
                            Gesture::None
                        }
                        Some(hand) => {
                            let rect = palm_crop_rect(&hand, width, height);
                            match landmarker.detect(&rgb, width, height, &rect) {
                                None => {
                                    skeleton.log(&ImageAnnotations::default());
                                    Gesture::None
                                }
                                Some(landmarks) => {
                                    let gesture = classify_gesture(&landmarks);
                                    skeleton.log(&skeleton_annotations(&landmarks, &rect, gesture));
                                    gesture
                                }
                            }
                        }
                    },
                };
                brain.update(gesture);
                let (linear, angular) = brain.velocity();
                cmd_vel.send(&twist(linear, angular))?;
                if brain.committed() != last_committed {
                    last_committed = brain.committed();
                    tracing::info!("pet command: {last_committed:?}");
                }
            }
        }
    }

    tracing::info!("halting");
    let _ = cmd_vel.send(&twist(0.0, 0.0));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn landmark_model_executes_through_tract() {
        let model = crate::perception::onnx::OnnxModel::load(&default_landmark_model())
            .expect("load landmark model");
        let outputs = model
            .run(
                &vec![0.0f32; LANDMARK_INPUT * LANDMARK_INPUT * RGB_CHANNELS],
                &[1, LANDMARK_INPUT, LANDMARK_INPUT, RGB_CHANNELS],
            )
            .expect("tract must execute the landmark model graph");
        assert!(outputs
            .iter()
            .any(|output| output.data.len() == LANDMARK_COUNT * 3));
    }

    #[test]
    fn brain_debounces_before_committing() {
        let mut brain = PetBrain::new();
        for _ in 0..DEBOUNCE_FRAMES - 1 {
            brain.update(Gesture::Point);
        }
        assert_eq!(brain.committed(), Gesture::None);
        brain.update(Gesture::Point);
        assert_eq!(brain.committed(), Gesture::Point);
    }

    #[test]
    fn watchdog_halt_disarms() {
        let mut brain = PetBrain::new();
        for _ in 0..DEBOUNCE_FRAMES {
            brain.update(Gesture::Point);
        }
        assert_eq!(brain.committed(), Gesture::Point);
        brain.halt();
        assert_eq!(brain.velocity(), (0.0, 0.0));
        assert_eq!(brain.committed(), Gesture::None);
    }
}
