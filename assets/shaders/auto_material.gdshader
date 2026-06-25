shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon, world_vertex_coords;

uniform sampler2D texture_ground_triplanar : source_color, filter_linear;
uniform sampler2D texture_wall_triplanar2 : source_color, filter_linear;
uniform float offset = 0.0;
uniform float fade = 0.0;
uniform sampler2D normal_ground_triplanar : hint_normal, filter_linear;
uniform sampler2D normal_wall_triplanar : hint_normal, filter_linear;
uniform float normal_strength_ground = 5.0;
uniform float normal_strength_wall = 15.0;

uniform sampler2D ground_gradient : source_color, filter_linear;
uniform sampler2D wall_gradient : source_color, filter_linear;

// New uniform to control the inversion
uniform bool invert_material = false;


// Triplanar mapping function
vec4 triplanar_texture(sampler2D p_sampler, vec3 p_weights, vec3 p_triplanar_pos) {
    vec4 samp = vec4(0.0);
    samp += texture(p_sampler, p_triplanar_pos.xy) * p_weights.z;
    samp += texture(p_sampler, p_triplanar_pos.xz) * p_weights.y;
    samp += texture(p_sampler, p_triplanar_pos.zy * vec2(-1.0, 1.0)) * p_weights.x;
    return samp;
}

uniform vec3 triplanar_scale = vec3(1.0, 1.0, 1.0);
uniform vec3 triplanar_offset;
uniform float triplanar_sharpness = 0.5;

varying vec3 triplanar_power_normal;
varying vec3 triplanar_pos;

void vertex() {
    // Calculate weights for triplanar mapping based on the normal's direction.
    triplanar_power_normal = pow(abs(NORMAL), vec3(triplanar_sharpness));
    triplanar_power_normal /= dot(triplanar_power_normal, vec3(1.0));
    
    // Calculate the position for sampling the triplanar texture.
    triplanar_pos = VERTEX * triplanar_scale + triplanar_offset;
    triplanar_pos *= vec3(1.0, -1.0, 1.0);
}

void fragment() {
    // Texture mapping for ground albedo.
    vec4 ground_albedo = triplanar_texture(texture_ground_triplanar, triplanar_power_normal, triplanar_pos);

    // Convert ground albedo to grayscale using a standard luma formula.
    vec3 luma_weights = vec3(0.299, 0.587, 0.114);
    float ground_luma = dot(ground_albedo.rgb, luma_weights);

    // Use a separate gradient texture to color the ground.
    vec4 final_ground_color = texture(ground_gradient, vec2(ground_luma, 0.5));

    // Texture mapping for wall albedo.
    vec4 wall_albedo = triplanar_texture(texture_wall_triplanar2, triplanar_power_normal, triplanar_pos);

    // Convert wall albedo to grayscale.
    float wall_luma = dot(wall_albedo.rgb, luma_weights);

    // Use a separate gradient texture to color the wall.
    vec4 final_wall_color = texture(wall_gradient, vec2(wall_luma, 0.5));

    // Get ground normal map data and decompress it from [0,1] to [-1,1].
    vec4 normal_ground_map_data = triplanar_texture(normal_ground_triplanar, triplanar_power_normal, triplanar_pos);
    vec3 normal_ground_tangent_space = normal_ground_map_data.rgb * 2.0 - 1.0;

    // Calculate the reconstructed tangent space normal.
    vec3 tangent_x = TANGENT * normal_ground_tangent_space.x;
    vec3 tangent_y = BINORMAL * normal_ground_tangent_space.y;
    float tangent_z_squared = 1.0 - normal_ground_tangent_space.x * normal_ground_tangent_space.x - normal_ground_tangent_space.y * normal_ground_tangent_space.y;
    vec3 tangent_z = NORMAL * sqrt(tangent_z_squared);
    vec3 reconstructed_normal = tangent_x + tangent_y + tangent_z;

    // Get the view space Y direction from the inverse view matrix.
    vec3 view_y_direction = (vec4(0.0, 1.0, 0.0, 0.0) * INV_VIEW_MATRIX).xyz;

    // Use a vertical gradient to mix between ground and wall textures based on the dot product of the reconstructed normal and the view space Y direction.
    float vertical_mix_factor = dot(reconstructed_normal, view_y_direction);
    
    // Smoothstep to create a faded transition.
    float lower_bound = offset - fade;
    float upper_bound = offset + fade;
    float blend_smoothstep = smoothstep(lower_bound, upper_bound, vertical_mix_factor);

    // Conditionally invert the blend_smoothstep based on the `invert_material` uniform.
    if (invert_material) {
        blend_smoothstep = 1.0 - blend_smoothstep;
    }

    // Mix the albedo textures based on the blend factor.
    vec4 final_albedo_mix = mix(final_ground_color, final_wall_color, blend_smoothstep);

    // Mix the roughness values based on the blend factor.
    float roughness_ground = 0.5;
    float roughness_wall = 0.9;
    float final_roughness = mix(roughness_ground, roughness_wall, blend_smoothstep);

    // Texture mapping for wall normal map.
    vec4 normal_wall = triplanar_texture(normal_wall_triplanar, triplanar_power_normal, triplanar_pos);

    // Mix the normal maps based on the blend factor.
    vec4 final_normal_map = mix(normal_ground_map_data, normal_wall, blend_smoothstep);

    // Mix the normal strengths based on the blend factor.
    float final_normal_strength = mix(normal_strength_ground, normal_strength_wall, blend_smoothstep);

    // Final material output.
    ALBEDO = final_albedo_mix.rgb;
    METALLIC = 0.0;	
    ROUGHNESS = final_roughness;
	//ROUGHNESS = 1.0;
    NORMAL_MAP = final_normal_map.rgb;
    NORMAL_MAP_DEPTH = final_normal_strength;
}