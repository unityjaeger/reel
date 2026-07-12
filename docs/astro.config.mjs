// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: "https://unityjaeger.github.io",
	base: "/reel/",
	integrations: [
		starlight({
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/unityjaeger/reel' }],
			title: 'Reel',
			description: 'Low-level Roblox animation solving for local playback and world-space queries.',
			sidebar: [
				{
					label: 'Guides',
					items: [
						
					],
				},
				{
					label: 'Reference',
					items: [{ autogenerate: { directory: 'reference' } }],
				},
			],
		}),
	],
});
