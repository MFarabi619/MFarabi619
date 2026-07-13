use std::path::PathBuf;

use zune_jpeg::{
    zune_core::{colorspace::ColorSpace, options::DecoderOptions},
    JpegDecoder,
};

use super::onnx::OnnxModel;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const MODEL_INPUT: usize = 192;
pub(crate) const RGB_CHANNELS: usize = 3;
const PALM_ANCHOR_COUNT: usize = 2016;
const REGRESSOR_WIDTH: usize = 18;
// Regressor row = [dx, dy, dw, dh] then 7 (x, y) palm keypoints.
const KEYPOINT_OFFSET: usize = 4;
const WRIST_KEYPOINT: usize = 0;
const MIDDLE_FINGER_KEYPOINT: usize = 2;
const MIN_SCORE: f32 = 0.5;

pub struct Config {
    pub model_path: PathBuf,
    pub min_score: f32,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            model_path: PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("assets/palm_detection.onnx"),
            min_score: MIN_SCORE,
        }
    }
}

pub struct Hand {
    pub center_x: f64,
    pub center_y: f64,
    pub width: f64,
    pub height: f64,
    pub score: f64,
    // Radians to rotate the crop so the wrist->middle-finger axis points up.
    pub rotation: f64,
}

pub(crate) fn decode_rgb(jpeg: &[u8]) -> Result<(Vec<u8>, usize, usize), BoxError> {
    let options = DecoderOptions::default().jpeg_set_out_colorspace(ColorSpace::RGB);
    let mut decoder = JpegDecoder::new_with_options(jpeg, options);
    let pixels = decoder
        .decode()
        .map_err(|error| format!("jpeg decode failed: {error}"))?;
    let info = decoder.info().ok_or("jpeg missing image info")?;
    Ok((pixels, info.width as usize, info.height as usize))
}

fn preprocess(rgb: &[u8], width: usize, height: usize) -> Vec<f32> {
    let mut input = vec![0.0f32; MODEL_INPUT * MODEL_INPUT * RGB_CHANNELS];
    for y in 0..MODEL_INPUT {
        let source_row = y * height / MODEL_INPUT;
        for x in 0..MODEL_INPUT {
            let source_column = x * width / MODEL_INPUT;
            let source = (source_row * width + source_column) * RGB_CHANNELS;
            let destination = (y * MODEL_INPUT + x) * RGB_CHANNELS;
            input[destination] = rgb[source] as f32 / 255.0;
            input[destination + 1] = rgb[source + 1] as f32 / 255.0;
            input[destination + 2] = rgb[source + 2] as f32 / 255.0;
        }
    }
    input
}

fn palm_anchors() -> Vec<(f32, f32)> {
    // palm-detection SSD anchor centers: stride-8 layer (2/cell) + merged stride-16 layers
    // (6/cell), 24*24*2 + 12*12*6 = 2016, matching the model's regressor/score rows.
    let groups = [(8usize, 2usize), (16usize, 6usize)];
    let mut anchors = Vec::with_capacity(PALM_ANCHOR_COUNT);
    for (stride, per_cell) in groups {
        let grid = MODEL_INPUT.div_ceil(stride);
        for row in 0..grid {
            for column in 0..grid {
                let center_x = (column as f32 + 0.5) / grid as f32;
                let center_y = (row as f32 + 0.5) / grid as f32;
                anchors.extend(std::iter::repeat_n((center_x, center_y), per_cell));
            }
        }
    }
    anchors
}

pub struct Detector {
    model: OnnxModel,
    anchors: Vec<(f32, f32)>,
}

impl Detector {
    pub fn load(config: &Config) -> Result<Self, BoxError> {
        Ok(Self {
            model: OnnxModel::load(&config.model_path)?,
            anchors: palm_anchors(),
        })
    }

    pub fn best_hand(
        &self,
        rgb: &[u8],
        width: usize,
        height: usize,
        min_score: f32,
    ) -> Option<Hand> {
        let outputs = self
            .model
            .run(
                &preprocess(rgb, width, height),
                &[1, MODEL_INPUT, MODEL_INPUT, RGB_CHANNELS],
            )
            .ok()?;

        // Two outputs: regressors [1, 2016, 18] and scores [1, 2016, 1]; bind by shape, not name.
        let (regressors, scores) = if outputs[0].shape.last() == Some(&REGRESSOR_WIDTH) {
            (&outputs[0].data, &outputs[1].data)
        } else {
            (&outputs[1].data, &outputs[0].data)
        };

        let anchor_count = self.anchors.len().min(scores.len());
        let (best_anchor, best_logit) = scores[..anchor_count]
            .iter()
            .copied()
            .enumerate()
            .max_by(|left, right| left.1.total_cmp(&right.1))?;

        let confidence = 1.0 / (1.0 + (-best_logit).exp());
        if confidence < min_score {
            return None;
        }

        // Decode: normalized center = delta / input_size + anchor_center; size = delta / input_size.
        let (anchor_x, anchor_y) = self.anchors[best_anchor];
        let input_size = MODEL_INPUT as f32;
        let base = best_anchor * REGRESSOR_WIDTH;
        let delta_x = regressors[base];
        let delta_y = regressors[base + 1];
        let delta_width = regressors[base + 2];
        let delta_height = regressors[base + 3];

        // Keypoints decode like the center; the wrist->middle-finger axis gives the crop rotation.
        let keypoint = |index: usize| {
            let offset = base + KEYPOINT_OFFSET + index * 2;
            (
                (regressors[offset] / input_size + anchor_x) as f64 * width as f64,
                (regressors[offset + 1] / input_size + anchor_y) as f64 * height as f64,
            )
        };
        let (wrist_x, wrist_y) = keypoint(WRIST_KEYPOINT);
        let (middle_x, middle_y) = keypoint(MIDDLE_FINGER_KEYPOINT);
        let rotation =
            std::f64::consts::FRAC_PI_2 - (-(middle_y - wrist_y)).atan2(middle_x - wrist_x);

        Some(Hand {
            center_x: (delta_x / input_size + anchor_x) as f64,
            center_y: (delta_y / input_size + anchor_y) as f64,
            width: (delta_width / input_size).abs() as f64,
            height: (delta_height / input_size).abs() as f64,
            score: confidence as f64,
            rotation,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn palm_model_executes_through_tract() {
        let model = crate::perception::onnx::OnnxModel::load(&Config::default().model_path)
            .expect("load palm model");
        let outputs = model
            .run(
                &vec![0.0f32; MODEL_INPUT * MODEL_INPUT * RGB_CHANNELS],
                &[1, MODEL_INPUT, MODEL_INPUT, RGB_CHANNELS],
            )
            .expect("tract must execute the palm model graph");
        assert_eq!(outputs.len(), 2);
        assert!(outputs
            .iter()
            .any(|output| output.shape.last() == Some(&REGRESSOR_WIDTH)));
    }
}
