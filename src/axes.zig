const c = @cImport({
    @cInclude("epoxy/gl.h");
});
const Shader = @import("shader.zig").Shader;
const Vec3 = @import("math.zig").Vec3;
const Camera = @import("camera.zig").Camera;

pub const Axes = struct {
    shader: Shader,
    vao: c_uint,
    n_elements_per_axis: u32,

    pub fn init() !Axes {
        const size = 100;
        const n = size * 2 + 1;
        var array: [n * 3]Vec3 = undefined;
        var i: f32 = -size;
        while (i <= size) : (i += 1) {
            const index = @floatToInt(u32, i + size);
            array[index] = Vec3.init(i, 0, 0);
            array[index + n] = Vec3.init(0, i, 0);
            array[index + n * 2] = Vec3.init(0, 0, i);
        }

        var vao: c.GLuint = undefined;
        c.glGenVertexArrays(1, &vao);
        var vbo: c.GLuint = undefined;
        c.glGenBuffers(1, &vbo);
        c.glBindVertexArray(vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        c.glBufferData(c.GL_ARRAY_BUFFER, array.len * @sizeOf(Vec3), &array, c.GL_STATIC_DRAW);
        c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 0, null);
        c.glEnableVertexAttribArray(0);

        const shader_ = try Shader.init("shaders/axis_vertex.glsl", "shaders/axis_fragment.glsl");

        return Axes{ .shader = shader_, .vao = vao, .n_elements_per_axis = n };
    }

    pub fn draw(self: *Axes, camera: Camera) void {
        self.shader.use();
        defer self.shader.unuse();

        c.glBindVertexArray(self.vao);
        defer c.glBindVertexArray(0);

        const n: c_int = @intCast(c_int, self.n_elements_per_axis);
        c.glPointSize(10);
        const view = camera.get_view();

        // set color, matrices
        try self.shader.set_vec3("color", Vec3.init(1, 0, 0));
        try self.shader.set_mat4("projection", camera.projection);
        try self.shader.set_mat4("view", view);
        c.glDrawArrays(c.GL_POINTS, 0, n);
        c.glDrawArrays(c.GL_LINE_STRIP, 0, n);

        try self.shader.set_vec3("color", Vec3.init(0, 1, 0));
        try self.shader.set_mat4("projection", camera.projection);
        try self.shader.set_mat4("view", view);
        c.glDrawArrays(c.GL_POINTS, n, n);
        c.glDrawArrays(c.GL_LINE_STRIP, n, n);

        try self.shader.set_vec3("color", Vec3.init(0, 0, 1));
        try self.shader.set_mat4("projection", camera.projection);
        try self.shader.set_mat4("view", view);
        c.glDrawArrays(c.GL_POINTS, n * 2, n);
        c.glDrawArrays(c.GL_LINE_STRIP, n * 2, n);
    }
};
