// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	integrations: [
		starlight({
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
