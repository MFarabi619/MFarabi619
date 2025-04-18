const { join } = require('node:path')
const { NxAppWebpackPlugin } = require('@nx/webpack/app-plugin')

module.exports = {
  output: {
    path: join(__dirname, './dist/apps/admin'),
  },
  plugins: [
    new NxAppWebpackPlugin({
      // deleteOutputPath: true,
      target: 'node',
      compiler: 'tsc',
      main: './src/main.ts',
      tsConfig: './tsconfig.server.json',
      assets: ['./src/assets'],
      optimization: false,
      outputHashing: 'none',
      generatePackageJson: true,
    }),
  ],
}
