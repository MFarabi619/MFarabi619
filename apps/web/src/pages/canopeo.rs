use std::rc::Rc;

use crate::services::canopeo::{classify_in_place, Stats, Thresholds, PRESETS};
use dioxus::html::{FileData, HasFileData};
use dioxus::prelude::*;
use lucide_dioxus::{Image as ImageIcon, Leaf, RotateCcw, Upload};
use ui::components::button::{Button, ButtonSize, ButtonVariant};
use ui::components::toast::Toasts;
#[cfg(target_arch = "wasm32")]
use wasm_bindgen::JsCast;
#[cfg(target_arch = "wasm32")]
use wasm_bindgen_futures::JsFuture;

const FILE_INPUT_ID: &str = "canopeo-file-input";

const STORAGE_KEY_P1: &str = "canopeo_p1";
const STORAGE_KEY_P2: &str = "canopeo_p2";
const STORAGE_KEY_P3: &str = "canopeo_p3";

#[derive(Clone)]
struct LoadedImage {
    rgba: Vec<u8>,
    width: u32,
    height: u32,
    file_name: String,
}

#[component]
pub fn Canopeo() -> Element {
    let mut thresholds = use_signal(load_thresholds);
    let mut loaded = use_signal(|| None::<LoadedImage>);
    let mut stats = use_signal(|| None::<Stats>);
    let mut drag_active = use_signal(|| false);
    let mut preset_index = use_signal(|| 0usize);

    let original_canvas = use_signal(|| None::<Rc<MountedData>>);
    let mask_canvas = use_signal(|| None::<Rc<MountedData>>);

    let toasts = Toasts;

    use_effect(move || {
        let threshold_values = *thresholds.read();
        persist_thresholds(&threshold_values);

        let Some(image) = loaded.read().clone() else { return };
        let mut buffer = image.rgba.clone();
        let result = classify_in_place(&mut buffer, &threshold_values);
        if let Some(mounted) = mask_canvas.read().as_ref() {
            paint_canvas(mounted, &mut buffer, image.width, image.height);
        }
        stats.set(Some(result));
    });

    let fgcc = use_memo(move || stats().map(|computed| computed.fgcc()));
    let pixel_counts = use_memo(move || stats().map(|computed| (computed.green, computed.total)));
    let image_dims = use_memo(move || {
        loaded.read().as_ref().map(|image| (image.width, image.height))
    });
    let file_label = use_memo(move || {
        loaded.read().as_ref().map(|image| image.file_name.clone())
    });

    let load_first = move |files: Vec<FileData>| async move {
        let Some(file) = files.into_iter().next() else { return };
        let file_name = file.name();
        let bytes = match file.read_bytes().await {
            Ok(bytes) => bytes.to_vec(),
            Err(_) => {
                toasts.error(format!("Could not read {file_name}"), None);
                return;
            }
        };
        match decode_and_paint(&bytes, &file_name, original_canvas).await {
            Some(image) => {
                loaded.set(Some(image));
            }
            None => {
                toasts.error(format!("Could not decode {file_name}"), None);
            }
        }
    };

    rsx! {
        section { class: "space-y-4",
            header { class: "flex items-center justify-between flex-wrap gap-3",
                div { class: "flex items-center gap-2",
                    Leaf { class: "w-6 h-6 text-primary" }
                    div {
                        h1 { class: "text-2xl font-semibold leading-tight", "Canopeo" }
                        p { class: "text-xs text-muted-foreground",
                            "Fractional Green Canopy Cover · Patrignani & Ochsner, "
                            a {
                                href: "https://doi.org/10.2134/agronj15.0150",
                                target: "_blank",
                                class: "underline hover:text-foreground",
                                "Agron. J. 2015"
                            }
                        }
                    }
                }
                FgccBadge { fgcc: fgcc() }
            }

            div { class: "grid grid-cols-1 md:grid-cols-2 gap-4",
                // Original
                div { class: "rounded-lg border border-border bg-background/60 overflow-hidden",
                    div { class: "px-3 py-2 border-b border-border text-xs uppercase tracking-wide text-muted-foreground",
                        "Original"
                    }
                    div { class: "relative",
                        canvas {
                            class: if loaded.read().is_some() { "block w-full h-auto bg-black" } else { "hidden" },
                            onmounted: move |cx| original_canvas.clone().set(Some(cx.data())),
                        }
                        if loaded.read().is_none() {
                            DropZone {
                                drag_active: drag_active(),
                                file_label: file_label(),
                                on_drag_enter: move |_| drag_active.set(true),
                                on_drag_leave: move |_| drag_active.set(false),
                                on_files: move |files: Vec<FileData>| async move {
                                    drag_active.set(false);
                                    load_first(files).await;
                                },
                            }
                        }
                    }
                }

                // Mask
                div { class: "rounded-lg border border-border bg-background/60 overflow-hidden",
                    div { class: "px-3 py-2 border-b border-border text-xs uppercase tracking-wide text-muted-foreground",
                        "Green mask"
                    }
                    div { class: "relative",
                        canvas {
                            class: if loaded.read().is_some() { "block w-full h-auto bg-black" } else { "hidden" },
                            onmounted: move |cx| mask_canvas.clone().set(Some(cx.data())),
                        }
                        if loaded.read().is_none() {
                            div { class: "h-64 grid place-items-center text-sm text-muted-foreground",
                                "Mask will render here"
                            }
                        }
                    }
                }
            }

            input {
                id: FILE_INPUT_ID,
                r#type: "file",
                accept: "image/*",
                class: "hidden",
                onchange: move |event| async move {
                    drag_active.set(false);
                    load_first(event.files()).await;
                },
            }

            // Controls
            div { class: "rounded-lg border border-border bg-background/60 p-4 space-y-4",
                div { class: "flex items-center justify-between flex-wrap gap-3",
                    div { class: "flex items-center gap-2 text-sm",
                        span { class: "text-muted-foreground", "Crop preset:" }
                        select {
                            class: "bg-transparent border border-border rounded px-2 py-1 text-sm font-mono outline-none cursor-pointer",
                            value: preset_index().to_string(),
                            onchange: move |event| {
                                if let Ok(index) = event.value().parse::<usize>() {
                                    if let Some(preset) = PRESETS.get(index) {
                                        preset_index.set(index);
                                        thresholds.set(preset.thresholds);
                                    }
                                }
                            },
                            for (index, preset) in PRESETS.iter().enumerate() {
                                option { value: "{index}", "{preset.name}" }
                            }
                        }
                    }

                    Button {
                        variant: ButtonVariant::Ghost,
                        size: ButtonSize::Small,
                        on_click: move |_| {
                            thresholds.set(Thresholds::default());
                            preset_index.set(0);
                        },
                        icon_left: rsx! { RotateCcw { class: "w-3.5 h-3.5" } },
                        "Reset"
                    }
                }

                ThresholdSlider {
                    label: "P₁ — R/G threshold",
                    value: thresholds().p1,
                    min: 0.80,
                    max: 1.20,
                    step: 0.01,
                    decimals: 2,
                    on_input: move |value| {
                        let mut current = *thresholds.read();
                        current.p1 = value;
                        thresholds.set(current);
                    },
                }

                ThresholdSlider {
                    label: "P₂ — B/G threshold",
                    value: thresholds().p2,
                    min: 0.80,
                    max: 1.20,
                    step: 0.01,
                    decimals: 2,
                    on_input: move |value| {
                        let mut current = *thresholds.read();
                        current.p2 = value;
                        thresholds.set(current);
                    },
                }

                ThresholdSlider {
                    label: "P₃ — Excess green index (2G − R − B)",
                    value: thresholds().p3,
                    min: 0.0,
                    max: 60.0,
                    step: 1.0,
                    decimals: 0,
                    on_input: move |value| {
                        let mut current = *thresholds.read();
                        current.p3 = value;
                        thresholds.set(current);
                    },
                }
            }

            // Stats
            if let Some((width, height)) = image_dims() {
                div { class: "rounded-lg border border-border bg-background/60 p-4",
                    div { class: "grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm",
                        StatTile { label: "Dimensions", value: format!("{width} × {height}") }
                        if let Some((green, total)) = pixel_counts() {
                            StatTile { label: "Green pixels", value: format!("{green}") }
                            StatTile { label: "Total pixels", value: format!("{total}") }
                            StatTile {
                                label: "FGCC %",
                                value: format!("{:.2}%", 100.0 * (green as f32) / (total as f32)),
                            }
                        }
                    }
                }
            }
        }
    }
}

#[component]
fn FgccBadge(fgcc: Option<f32>) -> Element {
    let display = fgcc.map(|value| format!("{value:.3}")).unwrap_or_else(|| "—".to_string());
    let percent = fgcc.map(|value| format!("{:.1}%", value * 100.0)).unwrap_or_default();
    rsx! {
        div { class: "rounded-lg border border-border bg-background/60 px-4 py-2 text-right",
            div { class: "text-[10px] uppercase tracking-wide text-muted-foreground", "FGCC" }
            div { class: "flex items-baseline gap-2",
                span { class: "text-3xl font-mono font-semibold text-primary", "{display}" }
                span { class: "text-sm text-muted-foreground", "{percent}" }
            }
        }
    }
}

#[component]
fn DropZone(
    drag_active: bool,
    file_label: Option<String>,
    on_drag_enter: EventHandler<()>,
    on_drag_leave: EventHandler<()>,
    on_files: EventHandler<Vec<FileData>>,
) -> Element {
    let outline = if drag_active {
        "border-primary bg-primary/10"
    } else {
        "border-border hover:bg-muted/30"
    };
    rsx! {
        label {
            r#for: FILE_INPUT_ID,
            class: "h-64 w-full grid place-items-center cursor-pointer rounded-lg border-2 border-dashed transition-colors {outline}",
            ondragover: move |event| {
                event.prevent_default();
                on_drag_enter.call(());
            },
            ondragleave: move |_| on_drag_leave.call(()),
            ondrop: move |event| {
                event.prevent_default();
                on_files.call(event.files());
            },
            div { class: "flex flex-col items-center gap-2 text-center px-6",
                div { class: "w-10 h-10 rounded-full bg-muted grid place-items-center",
                    Upload { class: "w-5 h-5 text-muted-foreground" }
                }
                div { class: "text-sm",
                    span { class: "font-medium", "Drop a canopy image" }
                    span { class: "text-muted-foreground", " or click to browse" }
                }
                if let Some(name) = file_label {
                    span { class: "inline-flex items-center gap-1 text-xs font-mono text-muted-foreground",
                        ImageIcon { class: "w-3 h-3" }
                        "{name}"
                    }
                }
                span { class: "text-[11px] text-muted-foreground",
                    "JPEG · PNG · WebP — processed entirely in your browser"
                }
            }
        }
    }
}

#[component]
fn ThresholdSlider(
    label: &'static str,
    value: f32,
    min: f32,
    max: f32,
    step: f32,
    decimals: usize,
    on_input: EventHandler<f32>,
) -> Element {
    let formatted = format!("{:.*}", decimals, value);
    rsx! {
        div { class: "space-y-1",
            div { class: "flex items-center justify-between text-sm",
                span { class: "text-muted-foreground", "{label}" }
                span { class: "font-mono text-foreground", "{formatted}" }
            }
            input {
                r#type: "range",
                class: "w-full accent-primary cursor-pointer",
                min: "{min}",
                max: "{max}",
                step: "{step}",
                value: "{value}",
                oninput: move |event| {
                    if let Ok(parsed) = event.value().parse::<f32>() {
                        on_input.call(parsed);
                    }
                },
            }
        }
    }
}

#[component]
fn StatTile(label: &'static str, value: String) -> Element {
    rsx! {
        div {
            div { class: "text-[10px] uppercase tracking-wide text-muted-foreground", "{label}" }
            div { class: "text-base font-mono", "{value}" }
        }
    }
}

fn load_thresholds() -> Thresholds {
    let default = Thresholds::default();
    #[cfg(target_arch = "wasm32")]
    {
        let Some(storage) =
            web_sys::window().and_then(|window| window.local_storage().ok().flatten())
        else {
            return default;
        };
        let read = |key: &str, fallback: f32| -> f32 {
            storage
                .get_item(key)
                .ok()
                .flatten()
                .and_then(|raw| raw.parse::<f32>().ok())
                .unwrap_or(fallback)
        };
        return Thresholds {
            p1: read(STORAGE_KEY_P1, default.p1),
            p2: read(STORAGE_KEY_P2, default.p2),
            p3: read(STORAGE_KEY_P3, default.p3),
        };
    }
    #[cfg(not(target_arch = "wasm32"))]
    default
}

fn persist_thresholds(thresholds: &Thresholds) {
    #[cfg(target_arch = "wasm32")]
    {
        let Some(storage) =
            web_sys::window().and_then(|window| window.local_storage().ok().flatten())
        else {
            return;
        };
        let _ = storage.set_item(STORAGE_KEY_P1, &thresholds.p1.to_string());
        let _ = storage.set_item(STORAGE_KEY_P2, &thresholds.p2.to_string());
        let _ = storage.set_item(STORAGE_KEY_P3, &thresholds.p3.to_string());
    }
    #[cfg(not(target_arch = "wasm32"))]
    let _ = thresholds;
}

#[cfg(target_arch = "wasm32")]
async fn decode_and_paint(
    bytes: &[u8],
    file_name: &str,
    original_canvas: Signal<Option<Rc<MountedData>>>,
) -> Option<LoadedImage> {
    let array = js_sys::Uint8Array::new_with_length(bytes.len() as u32);
    array.copy_from(bytes);
    let parts = js_sys::Array::of1(&array.buffer());
    let blob = web_sys::Blob::new_with_u8_array_sequence(&parts).ok()?;

    let window = web_sys::window()?;
    let bitmap_promise = window.create_image_bitmap_with_blob(&blob).ok()?;
    let bitmap_value = JsFuture::from(bitmap_promise).await.ok()?;
    let bitmap: web_sys::ImageBitmap = bitmap_value.dyn_into().ok()?;
    let width = bitmap.width();
    let height = bitmap.height();
    if width == 0 || height == 0 {
        return None;
    }

    let mounted = original_canvas.read().clone()?;
    let canvas = canvas_from(&mounted)?;
    canvas.set_width(width);
    canvas.set_height(height);
    let context_value = canvas.get_context("2d").ok()??;
    let context: web_sys::CanvasRenderingContext2d = context_value.dyn_into().ok()?;
    context.draw_image_with_image_bitmap(&bitmap, 0.0, 0.0).ok()?;
    let image_data = context
        .get_image_data(0.0, 0.0, width as f64, height as f64)
        .ok()?;
    bitmap.close();

    Some(LoadedImage {
        rgba: image_data.data().0,
        width,
        height,
        file_name: file_name.to_string(),
    })
}

#[cfg(not(target_arch = "wasm32"))]
async fn decode_and_paint(
    _bytes: &[u8],
    _file_name: &str,
    _original_canvas: Signal<Option<Rc<MountedData>>>,
) -> Option<LoadedImage> {
    None
}

fn paint_canvas(mounted: &MountedData, rgba: &mut [u8], width: u32, height: u32) {
    #[cfg(target_arch = "wasm32")]
    {
        let Some(canvas) = canvas_from(mounted) else { return };
        canvas.set_width(width);
        canvas.set_height(height);
        let Ok(Some(context_value)) = canvas.get_context("2d") else { return };
        let Ok(context) = context_value.dyn_into::<web_sys::CanvasRenderingContext2d>() else {
            return;
        };
        let clamped = wasm_bindgen::Clamped(&rgba[..]);
        let Ok(image_data) =
            web_sys::ImageData::new_with_u8_clamped_array_and_sh(clamped, width, height)
        else {
            return;
        };
        let _ = context.put_image_data(&image_data, 0.0, 0.0);
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        let _ = (mounted, rgba, width, height);
    }
}

#[cfg(target_arch = "wasm32")]
fn canvas_from(mounted: &MountedData) -> Option<web_sys::HtmlCanvasElement> {
    mounted.downcast::<web_sys::Element>()?.clone().dyn_into().ok()
}
