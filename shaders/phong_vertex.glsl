#version 330 core

layout (location = 0) in vec3 coord;
layout (location = 1) in vec3 normal_;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

out vec3 normal;
out vec3 pos;

void main(void) {
    vec4 coord_model = model * vec4(coord, 1.0);
    gl_Position = projection * view * coord_model;
    pos = vec3(coord_model);
    normal = mat3(transpose(inverse(model))) * normal_;
}
