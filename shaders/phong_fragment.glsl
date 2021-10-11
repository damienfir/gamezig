#version 330


uniform vec3 color;
uniform vec3 viewer_pos;
uniform vec3 teleportation_target;
uniform int show_teleportation;
uniform int show_normals;

in vec3 normal;
in vec3 pos;

out vec4 FragColor;

// https://stackoverflow.com/questions/12964279/whats-the-origin-of-this-glsl-rand-one-liner
float rand(vec2 co){
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void main(void) {
    const float PI = 3.1415926535897932384626433832795;

    vec3 light_pos = vec3(5, 10, 15);
    vec3 light_dir = normalize(light_pos - pos);

    float diff = max(0, dot(light_dir, normal));

    vec3 light_dir_reflected = reflect(light_dir, normal);
    vec3 viewer_dir = normalize(viewer_pos - pos);
    float n = 10;
    float spec = ((n + 8.0) / (8.0*PI)) * pow(max(0.0, dot(-light_dir_reflected, viewer_dir)), n);

    vec3 light_color = vec3(1., 1., 1.);
    vec3 ambient = 0.3 * light_color;
    vec3 diffuse = 0.7 * diff * light_color;
    vec3 specular = 0.2 * spec * light_color;

    //    float noise = rand(pos.xy) * 0.2;
    if (show_normals > 0) {
        vec3 nor = (normal + 1.f) / 2.f;
        FragColor = vec4(nor, 1.0);
    } else {
        vec3 phong_color = (ambient + diffuse + specular) * color;
        vec3 spot = vec3(0);
        if (show_teleportation > 0) {
            spot = max(vec3(0.f), vec3(1) * (1-length(pos - teleportation_target)));
        }
        FragColor = vec4(phong_color + 0.3 * spot, 1.);
    }
}