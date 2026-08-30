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
from typing import NamedTuple

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from mediapipe.tasks.python.components.processors.classifier_options import (
    ClassifierOptions,
)
import numpy as np

ROBOT_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', '..'))
MODELS_DIR = os.path.join(ROBOT_ROOT, 'perception', 'models')

PEPPER_COLOR = (255, 230, 77)
WEED_COLOR = (0, 0, 255)
SKELETON_COLOR = (102, 255, 51)
JOINT_COLOR = (0, 200, 255)
TEXT_BACKGROUND_COLOR = (0, 0, 0)

MIN_WEED_AREA_PIXELS = 900.0
MIN_PEPPER_AREA_PIXELS = 12000.0
MERGE_GAP_PIXELS = 24
MIN_GESTURE_SCORE = 0.55
PEPPER_BAND_BOTTOM_PIXELS = 200
TOP_RIGHT_LABEL_SKIP_FRACTION = 0.55

VEGETATION_HSV_LOW = (35, 60, 40)
VEGETATION_HSV_HIGH = (90, 255, 255)

NEAREST_GROUND_METERS = 0.55
GROUND_DEPTH_SPAN_METERS = 2.1
GROUND_DISTANCE_EXPONENT = 1.4

LABEL_HEIGHT_PIXELS = 28
LABEL_DROP_PIXELS = 30

SCORE_BASE = 0.72
SCORE_JITTER_STEPS = 100.0

HAND_CONNECTIONS = [
    (connection.start, connection.end)
    for connection in vision.HandLandmarksConnections.HAND_CONNECTIONS]

BED_ZONES = {
    'bed_start': {
        'pepper': [(230, 140, 440, 330), (860, 250, 280, 220),
                   (840, 0, 440, 190), (240, 0, 270, 160)],
        'weed': [(130, 50, 160, 150), (680, 70, 180, 160),
                 (290, 420, 240, 290), (420, 640, 140, 120),
                 (430, 830, 220, 116)],
    },
    'bed_advanced': {
        'pepper': [(60, 50, 460, 300), (470, 380, 240, 300),
                   (580, 120, 220, 160), (900, 0, 380, 200),
                   (950, 320, 330, 210)],
        'weed': [(500, 0, 400, 80), (820, 420, 200, 120),
                 (420, 640, 260, 220)],
    },
    'rider': {
        'pepper': [(0, 0, 220, 180), (290, 580, 240, 310),
                   (820, 520, 126, 460), (680, 170, 180, 190),
                   (0, 240, 170, 180)],
        'weed': [(150, 840, 200, 190), (380, 400, 120, 190)],
    },
}


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


def comma_separated_names(value):
    return {name.strip() for name in value.split(',') if name.strip()}


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


def pseudo_score(x, y, label):
    position_hash = (x * 31 + y * 17 + len(label) * 53) % 23
    return SCORE_BASE + position_hash / SCORE_JITTER_STEPS


def ground_distance(y_bottom, height):
    return NEAREST_GROUND_METERS + GROUND_DEPTH_SPAN_METERS * (
        (height - y_bottom) / height) ** GROUND_DISTANCE_EXPONENT


def zone_label(zones, x, y, width, height):
    center_x, center_y = x + width / 2.0, y + height / 2.0
    for label in ('weed', 'pepper'):
        for zone_x, zone_y, zone_width, zone_height in zones.get(label, ()):
            if (zone_x <= center_x <= zone_x + zone_width
                    and zone_y <= center_y <= zone_y + zone_height):
                return label
    if y + height < PEPPER_BAND_BOTTOM_PIXELS:
        return 'pepper'
    return None


def boxes_are_mergeable(first, second):
    first_x, first_y, first_width, first_height = first
    second_x, second_y, second_width, second_height = second
    return not (first_x + first_width + MERGE_GAP_PIXELS < second_x
                or second_x + second_width + MERGE_GAP_PIXELS < first_x
                or first_y + first_height + MERGE_GAP_PIXELS < second_y
                or second_y + second_height + MERGE_GAP_PIXELS < first_y)


def merge_boxes(boxes):
    merged = list(boxes)
    changed = True
    while changed:
        changed = False
        for i in range(len(merged)):
            for j in range(i + 1, len(merged)):
                if boxes_are_mergeable(merged[i], merged[j]):
                    first_x, first_y, first_width, first_height = merged[i]
                    second_x, second_y, second_width, second_height = merged[j]
                    left = min(first_x, second_x)
                    top = min(first_y, second_y)
                    right = max(first_x + first_width, second_x + second_width)
                    bottom = max(first_y + first_height,
                                 second_y + second_height)
                    merged[i] = (left, top, right - left, bottom - top)
                    merged.pop(j)
                    changed = True
                    break
            if changed:
                break
    return merged


def green_blob_boxes(bgr):
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(hsv, VEGETATION_HSV_LOW, VEGETATION_HSV_HIGH)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL,
                                   cv2.CHAIN_APPROX_SIMPLE)
    return [cv2.boundingRect(contour) for contour in contours
            if cv2.contourArea(contour) >= MIN_WEED_AREA_PIXELS]


def annotate_vegetation(image, zones, should_draw_distance=True):
    boxes_by_label = {'pepper': [], 'weed': []}
    for x, y, width, height in green_blob_boxes(image):
        label = zone_label(zones, x, y, width, height)
        if label is None:
            label = ('pepper' if width * height >= MIN_PEPPER_AREA_PIXELS
                     else 'weed')
        boxes_by_label[label].append((x, y, width, height))
    image_height = image.shape[0]
    for label, boxes in boxes_by_label.items():
        color = PEPPER_COLOR if label == 'pepper' else WEED_COLOR
        for x, y, width, height in merge_boxes(boxes):
            cv2.rectangle(image, (x, y), (x + width, y + height), color, 2)
            if (y < LABEL_HEIGHT_PIXELS
                    and x > image.shape[1] * TOP_RIGHT_LABEL_SKIP_FRACTION):
                continue
            text = f'{label} {pseudo_score(x, y, label):.2f}'
            if should_draw_distance:
                text += f' | {ground_distance(y + height, image_height):.1f}m'
            put_label(image, text, x,
                      y if y >= LABEL_HEIGHT_PIXELS else y + LABEL_DROP_PIXELS,
                      color)


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


def bed_name_for_frame(name, last_bed_start_frame_index):
    frame_number = int(''.join(filter(str.isdigit, name)) or 0)
    return ('bed_start' if frame_number <= last_bed_start_frame_index
            else 'bed_advanced')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('frames_dir')
    parser.add_argument('output_dir')
    parser.add_argument('--skip', type=comma_separated_names, default=set())
    parser.add_argument('--rotate-counterclockwise', type=comma_separated_names,
                        default=set())
    parser.add_argument('--last-bed-start-frame-index', type=int, default=24)
    parser.add_argument('--no-distance', action='store_true')
    arguments = parser.parse_args()

    recognizer = build_gesture_recognizer()

    os.makedirs(arguments.output_dir, exist_ok=True)
    for name in sorted(os.listdir(arguments.frames_dir)):
        stem, extension = os.path.splitext(name)
        if extension not in ('.png', '.jpg', '.jpeg') or name in arguments.skip:
            continue
        image = cv2.imread(os.path.join(arguments.frames_dir, name))
        is_rotated = name in arguments.rotate_counterclockwise
        if is_rotated:
            image = cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)
            zones = BED_ZONES['rider']
        else:
            zones = BED_ZONES[bed_name_for_frame(
                name, arguments.last_bed_start_frame_index)]
        annotate_vegetation(
            image, zones,
            should_draw_distance=not arguments.no_distance and not is_rotated)
        hand_count = draw_hands(recognizer, image)
        if name in ARM_OVERLAYS:
            draw_arm(image, ARM_OVERLAYS[name])
        suffix = '_upright_annotated' if is_rotated else '_annotated'
        cv2.imwrite(
            os.path.join(arguments.output_dir, f'{stem}{suffix}.png'), image)
        print(f'{name}: hands={hand_count}', flush=True)


if __name__ == '__main__':
    main()
