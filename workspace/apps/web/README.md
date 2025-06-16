## Serve

Install [trunk] to build and serve the web application.

```sh
cargo install --locked trunk
```

Add compilation target `wasm32-unknown-unknown`:

```sh
rustup target add wasm32-unknown-unknown
```

Then serve it on your browser:

```sh
trunk serve
```

Now go to [http://localhost:8080](http://localhost:8080) and enjoy TUIs in your browser!

> Change `release` to `true` in [Trunk.toml](./Trunk.toml) for release builds

## Vercel Observability Features

To enable the following features, add these snippents to the `<body>` of the [index.html](./index.html)

### [Speed Insights]

```html
<script>
  window.si = window.si || function () { (window.siq = window.siq || []).push(arguments); };
</script>
<script defer src="/_vercel/speed-insights/script.js"></script>
```

### [Web Analytics]

```html
<script>
  window.va = window.va || function () { (window.vaq = window.vaq || []).push(arguments); };
</script>
<script defer src="/_vercel/insights/script.js"></script>
```
