const std = @import("std");
const c = @cImport({
    @cInclude("epoxy/gl.h");
    @cInclude("GLFW/glfw3.h");
});

const c_allocator = std.heap.c_allocator;

const window_width = 1920;
var window_height: u32 = undefined;
const window_ratio = 16.0 / 9.0;

fn compile_shader_from_source(filename: []const u8, name: []const u8, kind: c.GLenum) !c.GLuint {
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    var buffer: [5096]u8 = undefined;
    const bytes_read = try file.read(&buffer);
    const source = buffer[0..bytes_read];
    var vertex_shader = c.glCreateShader(kind);
    const source_ptr: ?[*]const u8 = source.ptr;
    const source_len = @intCast(c.GLint, source.len);
    c.glShaderSource(vertex_shader, 1, &source_ptr, &source_len);
    c.glCompileShader(vertex_shader);

    var ok: c.GLint = undefined;
    c.glGetShaderiv(vertex_shader, c.GL_COMPILE_STATUS, &ok);
    if (ok == 0) {
        var error_size: c.GLint = undefined;
        c.glGetShaderiv(vertex_shader, c.GL_INFO_LOG_LENGTH, &error_size);

        const log = try c_allocator.alloc(u8, @intCast(usize, error_size));
        c.glGetShaderInfoLog(vertex_shader, error_size, &error_size, log.ptr);
        std.debug.panic("Error compiling {s} shader: {s}", .{ name, log });
    }
    return vertex_shader;
}

fn compile(vertex: []const u8, fragment: []const u8) !c.GLuint {
    const vertex_shader = try compile_shader_from_source(vertex, "vertex", c.GL_VERTEX_SHADER);
    defer c.glDeleteShader(vertex_shader);
    const fragment_shader = try compile_shader_from_source(fragment, "fragment", c.GL_FRAGMENT_SHADER);
    defer c.glDeleteShader(fragment_shader);

    const program = c.glCreateProgram();
    c.glAttachShader(program, vertex_shader);
    c.glAttachShader(program, fragment_shader);
    c.glLinkProgram(program);

    var ok: c.GLint = undefined;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &ok);
    if (ok == 0) {
        var error_size: c.GLint = undefined;
        c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &error_size);

        const log = try c_allocator.alloc(u8, @intCast(usize, error_size));
        c.glGetProgramInfoLog(program, error_size, &error_size, log.ptr);
        std.debug.panic("Error linking program: {s}", .{log});
    }
    return program;
}

fn glGetUniformLocation(program: c.GLuint, name: []const u8) !c_int {
    const loc = c.glGetUniformLocation(program, name.ptr);
    if (loc == -1) {
        std.debug.panic("Cannot get uniform location: {s}", .{name});
    }
    return loc;
}

const Shader = struct {
    program: c.GLuint,

    fn use(self: *Shader) void {
        c.glUseProgram(self.program);
    }

    fn unuse(self: *Shader) void {
        c.glUseProgram(0);
    }

    fn set_vec3(self: *Shader, name: []const u8, vec: []const f32) !void {
        const loc = try glGetUniformLocation(self.program, name);
        c.glUniform3fv(loc, 1, vec.ptr);
    }

    fn set_mat4(self: *Shader, name: []const u8, mat: *const Mat4) !void {
        const loc = try glGetUniformLocation(self.program, name);
        c.glUniformMatrix4fv(loc, 1, c.GL_TRUE, &mat.data);
    }
};

const Vec3 = packed struct {
    x: f32,
    y: f32,
    z: f32,

    fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }
};

fn div(v: Vec3, a: f32) Vec3 {
    return Vec3.init(v.x / a, v.y / a, v.z / a);
}

fn sub(a: Vec3, b: Vec3) Vec3 {
    return Vec3.init(a.x - b.x, a.y - b.y, a.z - b.z);
}

fn cross(a: Vec3, b: Vec3) Vec3 {
    return Vec3.init(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

test "cross" {
    const v = cross(Vec3.init(1, 0, 0), Vec3.init(0, 1, 0));
    try std.testing.expect(v.x == 0);
    try std.testing.expect(v.y == 0);
    try std.testing.expect(v.z == 1);
}

fn norm(v: Vec3) f32 {
    return @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
}

fn normalize(v: Vec3) Vec3 {
    return div(v, norm(v));
}

test "vec normalize" {
    const v = normalize(Vec3.init(2, 0, 0));
    try std.testing.expect(v.x == 1);
    try std.testing.expect(v.y == 0);
    try std.testing.expect(v.z == 0);
}

const Mat4 = struct {
    data: [16]f32,

    fn zero() Mat4 {
        var data = [_]f32{0} ** 16;
        return Mat4{ .data = data };
    }

    fn eye() Mat4 {
        var mat = Mat4.zero();
        mat.data[0] = 1;
        mat.data[5] = 1;
        mat.data[10] = 1;
        mat.data[15] = 1;
        return mat;
    }

    fn perpective(near: f32, far: f32, right: f32, top: f32) Mat4 {
        var mat = Mat4.zero();
        mat.data[0] = near / right;
        mat.data[5] = near / top;
        mat.data[10] = -(far + near) / (far - near);
        mat.data[11] = -2 * far * near / (far - near);
        mat.data[14] = -1;
        return mat;
    }

    fn lookat(position: Vec3, target: Vec3, up: Vec3) Mat4 {
        const direction = normalize(sub(position, target));
        const right = normalize(cross(up, direction));
        const cam_up = cross(direction, right);

        var rot = Mat4.zero();
        rot.data[0] = right.x;
        rot.data[1] = right.y;
        rot.data[2] = right.z;
        rot.data[4] = cam_up.x;
        rot.data[5] = cam_up.y;
        rot.data[6] = cam_up.z;
        rot.data[8] = direction.x;
        rot.data[9] = direction.y;
        rot.data[10] = direction.z;
        rot.data[15] = 1;

        var trans = Mat4.eye();
        trans.data[3] = -position.x;
        trans.data[7] = -position.y;
        trans.data[11] = -position.z;

        return mul(rot, trans);
    }

    fn print(self: *const Mat4) void {
        std.debug.print("{d:.2} {d:.2} {d:.2} {d:.2}\n", .{ self.data[0], self.data[1], self.data[2], self.data[3] });
        std.debug.print("{d:.2} {d:.2} {d:.2} {d:.2}\n", .{ self.data[4], self.data[5], self.data[6], self.data[7] });
        std.debug.print("{d:.2} {d:.2} {d:.2} {d:.2}\n", .{ self.data[8], self.data[9], self.data[10], self.data[11] });
        std.debug.print("{d:.2} {d:.2} {d:.2} {d:.2}\n", .{ self.data[12], self.data[13], self.data[14], self.data[15] });
    }
};

fn mul(A: Mat4, B: Mat4) Mat4 {
    const a = &A.data;
    const b = &B.data;
    var C = Mat4{ .data = undefined };
    var d = &C.data;
    d[0] = a[0] * b[0] + a[1] * b[4] + a[2] * b[8] + a[3] * b[12];
    d[1] = a[0] * b[1] + a[1] * b[5] + a[2] * b[9] + a[3] * b[13];
    d[2] = a[0] * b[2] + a[1] * b[6] + a[2] * b[10] + a[3] * b[14];
    d[3] = a[0] * b[3] + a[1] * b[7] + a[2] * b[11] + a[3] * b[15];

    d[4] = a[4] * b[0] + a[5] * b[4] + a[6] * b[8] + a[7] * b[12];
    d[5] = a[4] * b[1] + a[5] * b[5] + a[6] * b[9] + a[7] * b[13];
    d[6] = a[4] * b[2] + a[5] * b[6] + a[6] * b[10] + a[7] * b[14];
    d[7] = a[4] * b[3] + a[5] * b[7] + a[6] * b[11] + a[7] * b[15];

    d[8] = a[8] * b[0] + a[9] * b[4] + a[10] * b[8] + a[11] * b[12];
    d[9] = a[8] * b[1] + a[9] * b[5] + a[10] * b[9] + a[11] * b[13];
    d[10] = a[8] * b[2] + a[9] * b[6] + a[10] * b[10] + a[11] * b[14];
    d[11] = a[8] * b[3] + a[9] * b[7] + a[10] * b[11] + a[11] * b[15];

    d[12] = a[12] * b[0] + a[13] * b[4] + a[14] * b[8] + a[15] * b[12];
    d[13] = a[12] * b[1] + a[13] * b[5] + a[14] * b[9] + a[15] * b[13];
    d[14] = a[12] * b[2] + a[13] * b[6] + a[14] * b[10] + a[15] * b[14];
    d[15] = a[12] * b[3] + a[13] * b[7] + a[14] * b[11] + a[15] * b[15];

    return C;
}

test "matrix multiplication" {
    var A = Mat4.eye();
    var B = Mat4.eye();
    B.data[0] = 2;
    const C = mul(A, B);
    try std.testing.expect(C.data[0] == 2);
}

const Axes = struct {
    shader: Shader,
    vao: c_uint,
    n_elements_per_axis: u32,

    fn init() !Axes {
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

        const shader = Shader{ .program = try compile("shaders/axis_vertex.glsl", "shaders/axis_fragment.glsl") };

        return Axes{ .shader = shader, .vao = vao, .n_elements_per_axis = n };
    }

    fn draw(self: *Axes) void {
        self.shader.use();
        defer self.shader.unuse();

        c.glBindVertexArray(self.vao);
        defer c.glBindVertexArray(0);

        const n: c_int = @intCast(c_int, self.n_elements_per_axis);
        c.glPointSize(10);

        const projection = Mat4.perpective(0.1, 100.0, 0.05, 0.05 / window_ratio);
        const position = Vec3.init(1, 4, 10);
        const direction = normalize(Vec3.init(-0, -0.2, -1));
        const up = Vec3.init(0, 1, 0);
        const view = Mat4.lookat(position, direction, up);

        // set color, matrices
        try self.shader.set_vec3("color", &[_]f32{ 1, 0, 0 });
        try self.shader.set_mat4("projection", &projection);
        try self.shader.set_mat4("view", &view);
        c.glDrawArrays(c.GL_POINTS, 0, n);
        c.glDrawArrays(c.GL_LINE_STRIP, 0, n);

        try self.shader.set_vec3("color", &[_]f32{ 0, 1, 0 });
        try self.shader.set_mat4("projection", &projection);
        try self.shader.set_mat4("view", &view);
        c.glDrawArrays(c.GL_POINTS, n, n * 2);
        c.glDrawArrays(c.GL_LINE_STRIP, n, n * 2);

        try self.shader.set_vec3("color", &[_]f32{ 0, 0, 1 });
        try self.shader.set_mat4("projection", &projection);
        try self.shader.set_mat4("view", &view);
        c.glDrawArrays(c.GL_POINTS, n * 2, n * 3);
        c.glDrawArrays(c.GL_LINE_STRIP, n * 2, n * 3);
    }
};

fn draw_cursor() void {
    c.glPointSize(5);
    c.glBegin(c.GL_POINTS);
    c.glColor3d(1, 1, 1);
    c.glVertex3d(0, 0, 0);
    c.glEnd();
}

var axes: Axes = undefined;

fn draw() void {
    axes.draw();
    draw_cursor();
}

fn glfw_key_callback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    if (key == c.GLFW_KEY_ESCAPE and action == c.GLFW_PRESS) {
        c.glfwSetWindowShouldClose(window, 1);
    }
}

pub fn main() !void {
    _ = c.glfwInit();
    window_height = window_width / window_ratio;
    c.glfwWindowHint(c.GLFW_SAMPLES, 4);
    var window = c.glfwCreateWindow(window_width, @intCast(c_int, window_height), "Game", null, null);
    c.glfwMakeContextCurrent(window);
    c.glfwSetWindowPos(window, 100, 100);

    _ = c.glfwSetKeyCallback(window, glfw_key_callback);

    if (c.glfwRawMouseMotionSupported() != 0)
        c.glfwSetInputMode(window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);

    // const shader = Shader{ .program = try compile("shaders/phong_vertex.glsl", "shaders/phong_fragment.glsl") };
    axes = try Axes.init();

    while (c.glfwWindowShouldClose(window) == 0) {
        draw();

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

    _ = c.glfwTerminate();
}
