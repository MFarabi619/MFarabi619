import type { CollectionConfig } from 'payload'

import { authenticated } from '../access/index';

export const Users: CollectionConfig = {
  slug: 'users',
  access: {
    admin: authenticated,
    create: authenticated,
    delete: authenticated,
    read: authenticated,
    update: authenticated,
  },
  admin: {
    defaultColumns: [
      'avatar',
      'firstName',
      'lastName',
      'email'
    ],
    useAsTitle: 'preferredDisplayName',
  },
  auth: true,
  fields: [
    {
      type:"row",
    fields:[
    {
      type: "collapsible",
      label: ({ data }) => data?.title || "Personal Information",
      fields: [
        {
          type: 'row',
          fields:[
        { name: "firstName", type: "text", label: "First Name" },
        { name: "middleName", type: "text", label: "Middle Name", admin: {hidden: true} },
        { name: "lastName", type: "text", label: "Last Name" },
        { name: "preferredDisplayName", type: "text", label: "Display Name" },
          ],
        },
        {
          name: "avatar",
          type: "upload",
          relationTo: "media",
          label: "Avatar",
        }
      ],
    },
    ]
    },
    {
      type: "collapsible",
      label: ({ data }) => data?.title || "Brand & Socials",
      admin: { position: "sidebar",
               readOnly: true
             },
      fields: [
        {
          name: "website",
          type: "text",
          label: "Personal Website",
        },
        {
          type: "collapsible",
          label: "LinkedIn",
          fields: [
            {
              name: "linkedinVanity",
              type: "text",
              label: "Handle",
              admin: { readOnly: true },
            },
            {
              name: "linkedinId",
              type: "text",
              label: "ID",
              admin: {
                condition: () => {
                  return false;
                },
              },
            },
            {
              name: "linkedinEmailVerified",
              label: "Verified Email",
              type: "checkbox",
              admin: {
                readOnly: true,
              },
            },
            {
              name: "linkedinLocale",
              type: "text",
              admin: {
                readOnly: true,
              },
            },
          ],
        },
        {
          type: "collapsible",
          label: "GitHub",
          fields: [
            {
              name: "githubUrl",
              type: "text",
              admin: {
                condition: () => {
                  return false;
                },
              },
            },
            {
              name: "githubEmail",
              type: "email",
            },
            {
              name: "githubId",
              type: "text",
              admin: {
                condition: () => {
                  return false;
                },
              },
            },
            {
              name: "githubAvatarUrl",
              type: "text",
              admin: {
                condition: () => {
                  return false;
                },
              },
            },
            {
              name: "githubType",
              type: "text",
              admin: {
                condition: () => {
                  return false;
                },
              },
            },
            {
              name: "githubHtmlUrl",
              type: "text",
            },
            {
              name: "githubName",
              type: "text",
              admin: {
                condition: () => {
                  return false;
                },
              },
            },
            {
              name: "githubBlog",
              type: "text",
            },
            {
              name: "githubLocation",
              type: "text",
              admin: {
                condition: () => {
                  return false;
                },
              },
            },
            {
              name: "githubHireable",
              type: "text",
              admin: {
                condition: () => {
                  return false;
                },
              },
            },
            {
              name: "githubPublicRepos",
              type: "text",
            },
            {
              name: "githubLinkedin",
              type: "text",
            },
            {
              name: "githubInstagram",
              type: "text",
            },
          ],
        },
        {
          type: "collapsible",
          label: "Discord",
          fields: [
            {
              name: "discordUsername",
              type: "text",
            },
            {
              name: "discordGlobalName",
              type: "text",
            },
            {
              name: "discordVerified",
              type: "checkbox",
            },
            {
              name: "discordDiscriminator",
              type: "text",
            },
            {
              name: "discordLocale",
              type: "text",
            },
            {
              name: "discordId",
              type: "text",
              admin: {
                readOnly: true,
                condition: () => {
                  return false;
                },
              },
            },
          ],
        },
        {
          type: "collapsible",
          label: "Google",
          fields: [
            { name: "googleEmail", type: "email" },
            {
              name: "googleEmailVerified",
              type: "checkbox",
            },
          ],
        },
      ],
    },
  ],
  timestamps: true,
}
