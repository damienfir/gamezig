const std = @import("std");
const c = @cImport({
    @cInclude("epoxy/gl.h");
    @cInclude("GLFW/glfw3.h");
});
const shader = @import("shader.zig");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const window_width = 1920;
var window_height: u32 = undefined;
const window_ratio = 16.0 / 9.0;

const Axes = struct {
    shader: shader.Shader,
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

        const shader_ = try shader.Shader.init("shaders/axis_vertex.glsl", "shaders/axis_fragment.glsl");

        return Axes{ .shader = shader_, .vao = vao, .n_elements_per_axis = n };
    }

    fn draw(self: *Axes) void {
        self.shader.use();
        defer self.shader.unuse();

        c.glBindVertexArray(self.vao);
        defer c.glBindVertexArray(0);

        const n: c_int = @intCast(c_int, self.n_elements_per_axis);
        c.glPointSize(10);

        // set color, matrices
        try self.shader.set_vec3("color", &[_]f32{ 1, 0, 0 });
        try self.shader.set_mat4("projection", &camera.projection);
        try self.shader.set_mat4("view", &camera.get_view());
        c.glDrawArrays(c.GL_POINTS, 0, n);
        c.glDrawArrays(c.GL_LINE_STRIP, 0, n);

        try self.shader.set_vec3("color", &[_]f32{ 0, 1, 0 });
        try self.shader.set_mat4("projection", &camera.projection);
        try self.shader.set_mat4("view", &camera.get_view());
        c.glDrawArrays(c.GL_POINTS, n, n * 2);
        c.glDrawArrays(c.GL_LINE_STRIP, n, n * 2);

        try self.shader.set_vec3("color", &[_]f32{ 0, 0, 1 });
        try self.shader.set_mat4("projection", &camera.projection);
        try self.shader.set_mat4("view", &camera.get_view());
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

const Camera = struct {
    projection: Mat4,
    position: Vec3,
    direction: Vec3,
    up: Vec3,
    speed: f32,

    fn init() Camera {
        return Camera{ .projection = Mat4.perpective(0.1, 100.0, 0.05, 0.05 / window_ratio), .position = Vec3.init(1, 4, 10), .direction = Vec3.init(-0, -0.2, -1).normalize(), .up = Vec3.init(0, 1, 0), .speed = 5 };
    }

    fn get_view(self: Camera) Mat4 {
        return Mat4.lookat(self.position, self.position.add(self.direction), self.up);
    }

    fn get_horizontal_vector(self: Camera) Vec3 {
        return self.direction.cross(self.up).normalize();
    }

    fn rotate_direction(self: *Camera, dx: f32, dy: f32) void {
        var dir = self.direction.add(self.direction.cross(self.up).normalize().scale(dx * 0.002));
        dir = dir.add(self.up.scale(dy * 0.002));
        self.direction = dir.normalize();
    }
};

var axes: Axes = undefined;

fn draw() void {
    c.glClearColor(0, 0, 0, 0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    axes.draw();
    draw_cursor();
}

const Controls = struct { move_forwards: bool, move_backwards: bool, move_left: bool, move_right: bool, dx: f32, dy: f32 };
var controls: Controls = undefined;
var camera = Camera.init();

fn update(dt: f32) void {
    var velocity = Vec3.init(0, 0, 0);
    if (controls.move_forwards) {
        velocity = velocity.add(camera.direction);
    } else if (controls.move_backwards) {
        velocity = velocity.sub(camera.direction);
    }

    if (controls.move_right) {
        velocity = velocity.add(camera.get_horizontal_vector());
    } else if (controls.move_left) {
        velocity = velocity.sub(camera.get_horizontal_vector());
    }

    velocity = velocity.scale(camera.speed);

    camera.position = camera.position.add(velocity.scale(dt));

    camera.rotate_direction(controls.dx, controls.dy);
    controls.dx = 0;
    controls.dy = 0;
}

fn glfw_key_callback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    if (key == c.GLFW_KEY_ESCAPE and action == c.GLFW_PRESS) {
        c.glfwSetWindowShouldClose(window, 1);
    }

    if (key == c.GLFW_KEY_W) {
        if (action == c.GLFW_PRESS) {
            controls.move_backwards = false;
            controls.move_forwards = true;
        } else if (action == c.GLFW_RELEASE) {
            controls.move_forwards = false;
        }
    }

    if (key == c.GLFW_KEY_S) {
        if (action == c.GLFW_PRESS) {
            controls.move_forwards = false;
            controls.move_backwards = true;
        } else if (action == c.GLFW_RELEASE) {
            controls.move_backwards = false;
        }
    }

    if (key == c.GLFW_KEY_A) {
        if (action == c.GLFW_PRESS) {
            controls.move_right = false;
            controls.move_left = true;
        } else if (action == c.GLFW_RELEASE) {
            controls.move_left = false;
        }
    }

    if (key == c.GLFW_KEY_D) {
        if (action == c.GLFW_PRESS) {
            controls.move_left = false;
            controls.move_right = true;
        } else if (action == c.GLFW_RELEASE) {
            controls.move_right = false;
        }
    }
}

fn Pair(comptime T: type) type {
    return struct { a: T, b: T };
}

const Delta = struct {
    prev_x: f32,
    prev_y: f32,
    already_moved: bool,

    fn init() Delta {
        return Delta{ .prev_x = 0, .prev_y = 0, .already_moved = false };
    }

    fn get_delta(self: *Delta, x: f32, y: f32) Pair(f32) {
        if (!self.already_moved) {
            self.already_moved = true;
            self.prev_x = x;
            self.prev_y = y;
        }
        const dx = x - self.prev_x;
        const dy = y - self.prev_y;
        self.prev_x = x;
        self.prev_y = y;
        return Pair(f32){ .a = dx, .b = dy };
    }
};

var mouse_throttle: std.time.Timer = undefined;
var mouse_delta = Delta.init();

fn glfw_cursor_callback(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(.C) void {
    if (mouse_throttle.read() < @floatToInt(u64, (1.0 / 60.0) * 1e9)) {
        return;
    }
    mouse_throttle.reset();

    const delta = mouse_delta.get_delta(@floatCast(f32, xpos), @floatCast(f32, ypos));
    controls.dx = delta.a;
    controls.dy = -delta.b;
}

pub fn main() !void {
    _ = c.glfwInit();
    window_height = window_width / window_ratio;
    c.glfwWindowHint(c.GLFW_SAMPLES, 4);
    var window = c.glfwCreateWindow(window_width, @intCast(c_int, window_height), "Game", null, null);
    c.glfwMakeContextCurrent(window);
    c.glfwSetWindowPos(window, 100, 100);

    _ = c.glfwSetKeyCallback(window, glfw_key_callback);

    mouse_throttle = try std.time.Timer.start();
    _ = c.glfwSetCursorPosCallback(window, glfw_cursor_callback);

    _ = c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);

    if (c.glfwRawMouseMotionSupported() != 0)
        c.glfwSetInputMode(window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);

    axes = try Axes.init();

    var timer = try std.time.Timer.start();

    while (c.glfwWindowShouldClose(window) == 0) {
        const dt = @intToFloat(f32, timer.lap()) / 1e9;
        update(dt);

        draw();

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

    _ = c.glfwTerminate();
}
