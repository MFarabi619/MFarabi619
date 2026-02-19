module.exports = {
  content: [
    "./src/**/*.{rs,html,css}",
    "../../libs/ui/src/**/*.{rs,html,css}",
    `${process.env.HOME}/.cargo/git/checkouts/lumen-blocks-*/2675507/blocks/src/**/*.rs`,
  ],
  theme: {
    extend: {},
  },
  plugins: [],
};
