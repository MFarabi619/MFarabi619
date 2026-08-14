declare module "draco3dgltf" {
  const draco3d: {
    createEncoderModule(options?: object): Promise<unknown>;
    createDecoderModule(options?: object): Promise<unknown>;
  };
  export default draco3d;
}
