use std::{path::Path, sync::Arc};

use tract_onnx::prelude::*;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

pub struct OnnxOutput {
    pub shape: Vec<usize>,
    pub data: Vec<f32>,
}

pub struct OnnxModel {
    plan: Arc<TypedRunnableModel>,
}

impl OnnxModel {
    pub fn load(path: &Path) -> Result<Self, BoxError> {
        let plan = tract_onnx::onnx()
            .model_for_path(path)
            .map_err(|error| format!("tract load {}: {error}", path.display()))?
            .into_optimized()
            .map_err(|error| format!("tract optimize: {error}"))?
            .into_runnable()
            .map_err(|error| format!("tract runnable: {error}"))?;
        Ok(Self { plan })
    }

    // Runs a row-major NHWC f32 input; returns each output's shape + flat data in graph order.
    pub fn run(&self, input: &[f32], input_shape: &[usize]) -> Result<Vec<OnnxOutput>, BoxError> {
        let tensor = Tensor::from_shape(input_shape, input)
            .map_err(|error| format!("tract tensor: {error}"))?;
        let outputs = self
            .plan
            .run(tvec!(tensor.into()))
            .map_err(|error| format!("tract run: {error}"))?;
        outputs
            .iter()
            .map(|value| {
                Ok(OnnxOutput {
                    shape: value.shape().to_vec(),
                    data: value
                        .view()
                        .as_slice::<f32>()
                        .map_err(|error| format!("tract extract: {error}"))?
                        .to_vec(),
                })
            })
            .collect()
    }
}
