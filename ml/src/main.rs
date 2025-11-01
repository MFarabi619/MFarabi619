use burn::{backend::Wgpu, tensor::Tensor};

type Backend = Wgpu;

fn main() {
    let device = Default::default();
    // creation of two tensors, the first with explicit values and the second one with ones, with the same shape as the first
    let tensor_1 = Tensor::<Backend, 2>::from_data([[2., 3.], [4., 5.]], &device);
    let tensor_2 = Tensor::<Backend, 2>::ones_like(&tensor_1);

    // print the element-wise addition (done with the WGPU backend) of the two tensors
    println!("{}", tensor_1 + tensor_2);
}
