import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import BookIcon from "~icons/lucide/book-open";
import GithubIcon from "~icons/simple-icons/github";
import LinkedinIcon from "~icons/simple-icons/linkedin";

export const baseOptions: BaseLayoutProps = {
  nav: {
    title: (
      <>
        <img src="/symbol.png" alt="" className="size-6" />
        <span className="font-display">Tandem Robotics</span>
      </>
    ),
  },
  links: [
    {
      type: "icon",
      label: "Documentation",
      text: "Documentation",
      icon: <BookIcon />,
      url: "/docs",
    },
    {
      type: "icon",
      label: "LinkedIn",
      text: "LinkedIn",
      icon: <LinkedinIcon />,
      url: "https://www.linkedin.com/company/tandemrobotics/",
      external: true,
    },
    {
      type: "icon",
      label: "GitHub",
      text: "GitHub",
      icon: <GithubIcon />,
      url: "https://github.com/tandemrobotics",
      external: true,
    },
  ],
};
