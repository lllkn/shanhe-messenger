shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;

// 仅补绘被附近低矮铺面盖住的部分，普通箭头仍由正常深度材质绘制。
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 guide_color : source_color = vec4(1.0, 0.8, 0.31, 0.93);
uniform float surface_height = 0.65;
uniform float surface_reach = 0.9;
varying vec3 marker_world;

void vertex() {
	marker_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 surface_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	surface_view /= surface_view.w;
	vec3 surface_world = (INV_VIEW_MATRIX * surface_view).xyz;
	float marker_depth = -(VIEW_MATRIX * vec4(marker_world, 1.0)).z;
	float height = surface_world.y - marker_world.y;
	vec3 normal = normalize(cross(dFdx(surface_world), dFdy(surface_world)));
	bool covered = -surface_view.z < marker_depth - 0.015;
	bool nearby_floor = height >= -0.02 && height <= surface_height
		&& distance(surface_world.xz, marker_world.xz) <= surface_reach
		&& abs(normal.y) >= 0.7;
	if (!covered || !nearby_floor) {
		discard;
	}
	ALBEDO = guide_color.rgb * COLOR.rgb;
	ALPHA = guide_color.a * COLOR.a;
}
