tailwind.config = {
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: 'var(--color-primary, oklch(0.205 0 0))',
          foreground: 'var(--color-primary-foreground, oklch(0.985 0 0))',
        },
        secondary: {
          DEFAULT: 'var(--color-secondary, oklch(0.97 0 0))',
          foreground: 'var(--color-secondary-foreground, oklch(0.205 0 0))',
        },
        muted: {
          DEFAULT: 'var(--color-muted, oklch(0.97 0 0))',
          foreground: 'var(--color-muted-foreground, oklch(0.556 0 0))',
        },
        accent: {
          DEFAULT: 'var(--color-accent, oklch(0.97 0 0))',
          foreground: 'var(--color-accent-foreground, oklch(0.205 0 0))',
        },
        destructive: 'var(--color-destructive, oklch(0.577 0.245 27.325))',
        border: 'var(--color-border, oklch(0.922 0 0))',
        input: 'var(--color-input, oklch(0.922 0 0))',
        ring: 'var(--color-ring, oklch(0.708 0 0))',
        background: 'var(--color-background, oklch(1 0 0))',
        foreground: 'var(--color-foreground, oklch(0.145 0 0))',
        card: {
          DEFAULT: 'var(--color-card, oklch(1 0 0))',
          foreground: 'var(--color-card-foreground, oklch(0.145 0 0))',
        },
        popover: {
          DEFAULT: 'var(--color-popover, oklch(1 0 0))',
          foreground: 'var(--color-popover-foreground, oklch(0.145 0 0))',
        },
        'chart-1': 'oklch(0.646 0.222 41.116)',
        'chart-2': 'oklch(0.6 0.118 184.704)',
        'chart-3': 'oklch(0.398 0.07 227.392)',
        'chart-4': 'oklch(0.828 0.189 84.429)',
        'chart-5': 'oklch(0.769 0.188 70.08)',
      },
      borderRadius: {
        'sm': 'calc(0.625rem - 4px)',
        'md': 'calc(0.625rem - 2px)',
        'lg': '0.625rem',
        'xl': 'calc(0.625rem + 4px)',
      }
    }
  }
}
