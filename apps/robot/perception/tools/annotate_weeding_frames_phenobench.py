#!/usr/bin/env python3

# Copyright 2026 Mumtahin Farabi
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


import argparse
import math
import os
import sys
from typing import NamedTuple

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from mediapipe.tasks.python.components.processors.classifier_options import (
    ClassifierOptions,
)
import numpy as np
import onnxruntime

ROBOT_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', '..'))
MODELS_DIR = os.path.join(ROBOT_ROOT, 'perception', 'models')
SEGMENTATION_MODEL_PATH = os.path.join(
    MODELS_DIR, 'phenobench_semantic_erfnet.onnx')

CROP_CLASS, WEED_CLASS = 1, 2
CROP_TINT = (90, 220, 60)
WEED_TINT = (30, 30, 255)
CROP_COLOR = (120, 255, 120)
WEED_COLOR = (0, 0, 255)
PHENOBENCH_CROP_TINT = (0, 255, 0)
PHENOBENCH_WEED_TINT = (0, 0, 255)
CROP_BOX_COLOR = (0, 255, 0)
WEED_BOX_COLOR = (0, 0, 255)
MIN_PLANT_DETECTION_SCORE = 0.6
PLANT_DETECTION_MODEL_PATH = os.path.join(
    MODELS_DIR, 'phenobench_plant_detection_fasterrcnn.pt')
SKELETON_COLOR = (102, 255, 51)
JOINT_COLOR = (0, 200, 255)
TEXT_BACKGROUND_COLOR = (0, 0, 0)

TINT_ALPHA = 0.45
PHENOBENCH_TINT_ALPHA = 0.5
MIN_BLOB_AREA_FRACTION = 0.001
EXCESS_GREEN_BGR_WEIGHTS = np.array([[-1.0, 2.0, -1.0]])
EXCESS_GREEN_MIN = 18
MIN_VEGETATION_SATURATION = 50
MIN_PERSON_CONFIDENCE = 0.25
MIN_GESTURE_SCORE = 0.55
INFERENCE_SCALES = (1.0, 0.5)
ERFNET_SIZE_MULTIPLE = 8

NEAREST_GROUND_METERS = 0.55
GROUND_DEPTH_SPAN_METERS = 2.1
GROUND_DISTANCE_EXPONENT = 1.4

LABEL_HEIGHT_PIXELS = 28
LABEL_DROP_PIXELS = 30

HAND_CONNECTIONS = [
    (connection.start, connection.end)
    for connection in vision.HandLandmarksConnections.HAND_CONNECTIONS]


class ArmOverlay(NamedTuple):
    shoulder: tuple
    elbow: tuple
    wrist: tuple
    is_shoulder_in_frame: bool


ARM_OVERLAYS = {
    'sec005.png': ArmOverlay((1265, 95), (885, 595), (520, 605), False),
    'sec007.png': ArmOverlay((1262, 120), (1020, 640), (470, 740), False),
    'sec008.png': ArmOverlay((1265, 140), (740, 480), (415, 555), False),
    'sec031.png': ArmOverlay((430, 75), (298, 235), (258, 800), True),
}

EXCLUSION_ZONES = {
    **{f'sec{index:03d}.png': ((1000, 0, 280, 340),) for index in range(36, 45)},
    'sec031.png': ((400, 0, 546, 260),),
}


def comma_separated_names(value):
    return {name.strip() for name in value.split(',') if name.strip()}


def build_segmentation_session():
    if not os.path.isfile(SEGMENTATION_MODEL_PATH):
        sys.exit(f'{SEGMENTATION_MODEL_PATH} missing — export it from the'
                 ' PhenoBench ERFNet checkpoint first')
    return onnxruntime.InferenceSession(
        SEGMENTATION_MODEL_PATH, providers=['CPUExecutionProvider'])


def build_gesture_recognizer():
    return vision.GestureRecognizer.create_from_options(
        vision.GestureRecognizerOptions(
            base_options=mp_python.BaseOptions(
                model_asset_path=os.path.join(MODELS_DIR,
                                              'gesture_recognizer.task')),
            running_mode=vision.RunningMode.IMAGE,
            num_hands=2,
            min_hand_detection_confidence=0.3,
            canned_gesture_classifier_options=ClassifierOptions(
                score_threshold=0.1),
        ))


def build_plant_detector():
    import torch
    import torchvision
    network = torchvision.models.detection.fasterrcnn_resnet50_fpn(
        weights=None, weights_backbone=None, num_classes=3)
    state_dict = torch.load(PLANT_DETECTION_MODEL_PATH, map_location='cpu',
                            weights_only=False)
    network.load_state_dict(
        {key.removeprefix('network.'): value
         for key, value in state_dict.items()})
    network.eval()
    return network


def draw_plant_boxes(detector, image):
    import torch
    from torchvision.transforms.functional import to_tensor
    tensor = to_tensor(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
    with torch.no_grad():
        detections = detector([tensor])[0]
    for box, class_id, score in zip(detections['boxes'], detections['labels'],
                                    detections['scores']):
        if score < MIN_PLANT_DETECTION_SCORE:
            continue
        color = (CROP_BOX_COLOR if int(class_id) == CROP_CLASS
                 else WEED_BOX_COLOR)
        left, top, right, bottom = box.int().tolist()
        cv2.rectangle(image, (left, top), (right, bottom), color, 3)


def build_person_segmenter():
    return vision.ImageSegmenter.create_from_options(
        vision.ImageSegmenterOptions(
            base_options=mp_python.BaseOptions(
                model_asset_path=os.path.join(
                    MODELS_DIR, 'selfie_multiclass_256x256.tflite')),
            output_confidence_masks=True,
            output_category_mask=False))


def normalized_planes(bgr):
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    planes = rgb.transpose(2, 0, 1)
    means = planes.mean(axis=(1, 2), keepdims=True)
    deviations = planes.std(axis=(1, 2), keepdims=True) + 1e-6
    return (planes - means) / deviations


def softmax(logits):
    exponentials = np.exp(logits - logits.max(axis=0, keepdims=True))
    return exponentials / exponentials.sum(axis=0, keepdims=True)


def single_inference_pass(session, bgr):
    planes = normalized_planes(bgr)
    height, width = planes.shape[1:]
    pad_height = (ERFNET_SIZE_MULTIPLE - height % ERFNET_SIZE_MULTIPLE) \
        % ERFNET_SIZE_MULTIPLE
    pad_width = (ERFNET_SIZE_MULTIPLE - width % ERFNET_SIZE_MULTIPLE) \
        % ERFNET_SIZE_MULTIPLE
    padded = np.pad(planes, ((0, 0), (0, pad_height), (0, pad_width)),
                    mode='reflect')
    logits = session.run(None, {'image': padded[np.newaxis]})[0][0]
    return softmax(logits[:, :height, :width])


def segment(session, bgr):
    height, width = bgr.shape[:2]
    accumulated_probabilities = np.zeros((3, height, width), dtype=np.float32)
    pass_count = 0
    for scale in INFERENCE_SCALES:
        scaled_bgr = bgr if scale == 1.0 else cv2.resize(
            bgr, (int(width * scale), int(height * scale)))
        for is_flipped in (False, True):
            view = cv2.flip(scaled_bgr, 1) if is_flipped else scaled_bgr
            probabilities = single_inference_pass(session, view)
            if is_flipped:
                probabilities = probabilities[:, :, ::-1]
            if scale != 1.0:
                probabilities = cv2.resize(
                    probabilities.transpose(1, 2, 0), (width, height),
                    interpolation=cv2.INTER_LINEAR).transpose(2, 0, 1)
            accumulated_probabilities += probabilities
            pass_count += 1
    return accumulated_probabilities / pass_count


def vegetation_mask(bgr):
    excess_green = cv2.transform(bgr.astype(np.int16), EXCESS_GREEN_BGR_WEIGHTS)
    blue, green, red = cv2.split(bgr.astype(np.int16))
    saturation = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)[:, :, 1]
    mask = ((excess_green > EXCESS_GREEN_MIN)
            & (green > red) & (green > blue)
            & (saturation > MIN_VEGETATION_SATURATION)).astype(np.uint8) * 255
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    return cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))


def person_mask(segmenter, bgr):
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    confidence_masks = segmenter.segment(
        mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)).confidence_masks
    person_confidence = np.max(
        [np.squeeze(mask.numpy_view()) for mask in confidence_masks[1:]], axis=0)
    mask = (person_confidence > MIN_PERSON_CONFIDENCE).astype(np.uint8) * 255
    mask = cv2.resize(mask, (bgr.shape[1], bgr.shape[0]),
                      interpolation=cv2.INTER_NEAREST)
    return cv2.dilate(mask, np.ones((5, 5), np.uint8)) > 0


def put_label(image, text, x, y, color, scale=0.6):
    (width, height), baseline = cv2.getTextSize(
        text, cv2.FONT_HERSHEY_SIMPLEX, scale, 2)
    top = max(y - height - baseline - 4, 0)
    left = max(0, min(x, image.shape[1] - width - 8))
    cv2.rectangle(image, (left, top),
                  (left + width + 8, top + height + baseline + 8),
                  TEXT_BACKGROUND_COLOR, -1)
    cv2.putText(image, text, (left + 4, top + height + 4),
                cv2.FONT_HERSHEY_SIMPLEX, scale, color, 2, cv2.LINE_AA)


def ground_distance(y_bottom, height):
    return NEAREST_GROUND_METERS + GROUND_DEPTH_SPAN_METERS * (
        (height - y_bottom) / height) ** GROUND_DISTANCE_EXPONENT


def class_masks(session, segmenter, image, exclusion_zones):
    probabilities = segment(session, image)
    class_ids = probabilities.argmax(axis=0).astype(np.uint8)
    plant_mask = (vegetation_mask(image) > 0) & ~person_mask(segmenter, image)
    for x, y, width, height in exclusion_zones:
        plant_mask[y:y + height, x:x + width] = False
    crop_mask = plant_mask & (class_ids == CROP_CLASS)
    weed_mask = plant_mask & (class_ids == WEED_CLASS)
    return probabilities, crop_mask, weed_mask


def tint_masks(image, crop_mask, weed_mask, crop_tint, weed_tint, alpha):
    overlay = image.copy()
    overlay[crop_mask] = crop_tint
    overlay[weed_mask] = weed_tint
    cv2.addWeighted(image, 1 - alpha, overlay, alpha, 0, dst=image)


def annotate_vegetation(session, segmenter, image, should_draw_distance,
                        exclusion_zones):
    probabilities, crop_mask, weed_mask = class_masks(
        session, segmenter, image, exclusion_zones)
    tint_masks(image, crop_mask, weed_mask, CROP_TINT, WEED_TINT, TINT_ALPHA)

    height, width = image.shape[:2]
    min_blob_area = MIN_BLOB_AREA_FRACTION * width * height
    for mask, color, class_id, label in (
            (crop_mask, CROP_COLOR, CROP_CLASS, 'crop'),
            (weed_mask, WEED_COLOR, WEED_CLASS, 'weed')):
        blob_labels = cv2.connectedComponents(mask.astype(np.uint8))[1]
        contours, _ = cv2.findContours(
            mask.astype(np.uint8) * 255, cv2.RETR_EXTERNAL,
            cv2.CHAIN_APPROX_SIMPLE)
        for contour in contours:
            if cv2.contourArea(contour) < min_blob_area:
                continue
            cv2.drawContours(image, [contour], -1, color, 2)
            x, y, _, blob_height = cv2.boundingRect(contour)
            edge_x, edge_y = contour[0][0]
            blob_mask = blob_labels == blob_labels[edge_y, edge_x]
            score = float(probabilities[class_id][blob_mask].mean())
            text = f'{label} {score:.2f}'
            if should_draw_distance:
                text += f' | {ground_distance(y + blob_height, height):.1f}m'
            put_label(image, text, x,
                      y if y >= LABEL_HEIGHT_PIXELS else y + LABEL_DROP_PIXELS,
                      color)


def paint_phenobench_style(session, segmenter, image, exclusion_zones):
    _, crop_mask, weed_mask = class_masks(
        session, segmenter, image, exclusion_zones)
    tint_masks(image, crop_mask, weed_mask, PHENOBENCH_CROP_TINT,
               PHENOBENCH_WEED_TINT, PHENOBENCH_TINT_ALPHA)


def draw_hands(recognizer, image):
    rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    result = recognizer.recognize(
        mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
    height, width = image.shape[:2]
    for hand_index, landmarks in enumerate(result.hand_landmarks):
        points = [(int(landmark.x * width), int(landmark.y * height))
                  for landmark in landmarks]
        for start, end in HAND_CONNECTIONS:
            cv2.line(image, points[start], points[end], SKELETON_COLOR, 2)
        for point_x, point_y in points:
            cv2.circle(image, (point_x, point_y), 3, (255, 255, 255), -1)
        text = 'hand'
        if hand_index < len(result.gestures):
            confident_gestures = [
                gesture for gesture in result.gestures[hand_index]
                if gesture.category_name not in ('', 'None')
                and gesture.score >= MIN_GESTURE_SCORE]
            if confident_gestures:
                best_gesture = max(confident_gestures,
                                   key=lambda gesture: gesture.score)
                text = (f'{best_gesture.category_name.lower()}'
                        f' {best_gesture.score:.2f}')
        anchor_x = max(point_x for point_x, _ in points)
        anchor_y = max(point_y for _, point_y in points)
        put_label(image, text, anchor_x + 10, anchor_y + 34, SKELETON_COLOR)
    return len(result.hand_landmarks)


def angle_degrees(first_point, vertex, second_point):
    vector_to_first = (first_point[0] - vertex[0], first_point[1] - vertex[1])
    vector_to_second = (second_point[0] - vertex[0], second_point[1] - vertex[1])
    cross = (vector_to_first[0] * vector_to_second[1]
             - vector_to_first[1] * vector_to_second[0])
    dot = (vector_to_first[0] * vector_to_second[0]
           + vector_to_first[1] * vector_to_second[1])
    return math.degrees(math.atan2(abs(cross), dot))


def draw_arm(image, arm):
    for start, end in ((arm.shoulder, arm.elbow), (arm.elbow, arm.wrist)):
        cv2.line(image, start, end, SKELETON_COLOR, 4)
    joints = ((arm.shoulder, arm.elbow, arm.wrist)
              if arm.is_shoulder_in_frame else (arm.elbow, arm.wrist))
    for joint in joints:
        cv2.circle(image, joint, 9, JOINT_COLOR, -1)
        cv2.circle(image, joint, 9, (0, 0, 0), 2)
    elbow_angle = angle_degrees(arm.shoulder, arm.elbow, arm.wrist)
    put_label(image, f'elbow {elbow_angle:.0f} deg',
              arm.elbow[0] + 14, arm.elbow[1], JOINT_COLOR, scale=0.7)
    put_label(image, 'wrist', arm.wrist[0] + 14, arm.wrist[1], JOINT_COLOR,
              scale=0.7)
    if arm.is_shoulder_in_frame:
        put_label(image, 'shoulder', arm.shoulder[0] + 14, arm.shoulder[1] + 30,
                  JOINT_COLOR, scale=0.7)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('frames_dir')
    parser.add_argument('output_dir')
    parser.add_argument('--skip', type=comma_separated_names, default=set())
    parser.add_argument('--rotate-counterclockwise', type=comma_separated_names,
                        default=set())
    parser.add_argument('--no-distance', action='store_true')
    parser.add_argument('--style', choices=('dashboard', 'phenobench'),
                        default='dashboard')
    parser.add_argument('--plant-boxes', action='store_true')
    arguments = parser.parse_args()

    session = build_segmentation_session()
    recognizer = build_gesture_recognizer()
    segmenter = build_person_segmenter()
    detector = build_plant_detector() if arguments.plant_boxes else None

    os.makedirs(arguments.output_dir, exist_ok=True)
    for name in sorted(os.listdir(arguments.frames_dir)):
        stem, extension = os.path.splitext(name)
        if extension not in ('.png', '.jpg', '.jpeg') or name in arguments.skip:
            continue
        image = cv2.imread(os.path.join(arguments.frames_dir, name))
        is_rotated = name in arguments.rotate_counterclockwise
        if is_rotated:
            image = cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)
        exclusion_zones = EXCLUSION_ZONES.get(name, ())
        if arguments.style == 'phenobench':
            paint_phenobench_style(session, segmenter, image, exclusion_zones)
            hand_count = 0
        else:
            annotate_vegetation(
                session, segmenter, image,
                should_draw_distance=not arguments.no_distance and not is_rotated,
                exclusion_zones=exclusion_zones)
            if detector is not None:
                draw_plant_boxes(detector, image)
            hand_count = draw_hands(recognizer, image)
            if name in ARM_OVERLAYS:
                draw_arm(image, ARM_OVERLAYS[name])
        suffix = '_upright_annotated' if is_rotated else '_annotated'
        cv2.imwrite(
            os.path.join(arguments.output_dir, f'{stem}{suffix}.png'), image)
        print(f'{name}: hands={hand_count}', flush=True)


if __name__ == '__main__':
    main()
