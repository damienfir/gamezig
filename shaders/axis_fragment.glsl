#version 330

uniform vec3 color;

out vec4 FragColor;

void main(void) {
    FragColor = vec4(color, 1.0);
}