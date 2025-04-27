/* eslint-disable node/prefer-global/process */
import type { GlobalConfig } from "payload";

export const Constants: GlobalConfig = {
  slug: "constants",
  access: {
    read: () => true,
  },
  versions: {
    drafts: true,
  },
  fields: [
  ],
};
