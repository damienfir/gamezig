const std = @import("std");
const c = @cImport({
    @cInclude("epoxy/gl.h");
    @cInclude("GLFW/glfw3.h");
});
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Axes = @import("axes.zig").Axes;
const Camera = @import("camera.zig").Camera;
const Shader = @import("shader.zig").Shader;

const GLBuffer = struct { vao: c.GLuint, shader: Shader, n_vertices: u32,
// TODO: move color to mesh
color: Vec3 };

const Mesh = struct { vertices: []Vec3, normals: []Vec3, color: Vec3 };

const Entity = struct { gl_buffer: usize, mesh: usize, position: Vec3 };

const Grid = struct {
    rows: u32,
    cols: u32,
    start: u32,
    end: u32,
    entities: []Entity,

    const Point = struct {
        x: u32,
        y: u32,

        fn init(x: u32, y: u32) Point {
            return Point{ .x = x, .y = y };
        }
    };

    fn init(rows: u32, cols: u32) !Grid {
        var self: Grid = undefined;
        self.rows = rows;
        self.cols = cols;
        self.entities = try gpa.allocator.alloc(Entity, rows * cols);
        return self;
    }

    fn index_from_point(self: Grid, p: Point) u32 {
        return p.y * self.cols + p.x;
    }

    fn point_from_index(self: Grid, index: u32) Point {
        return Point{ .x = index % self.cols, .y = index / self.cols };
    }

    fn world_from_point(self: Grid, p: Point) Vec3 {
        const x = @intToFloat(f32, p.x);
        const y = @intToFloat(f32, p.y);
        return Vec3{ .x = x, .y = 0, .z = y };
    }

    fn index_from_world(self: Grid, p: Vec3) u32 {
        return self.index_from_point(Point{ .x = @floatToInt(u32, p.x), .y = @floatToInt(u32, p.y) });
    }
};

const CellType = enum { Floor, Start, End, HorizontalWall, VerticalWall, HorizontalHedge, VerticalHedge, Platform, RaisedPlatform };

fn make_mesh_from_cell_type(cell: CellType) !Mesh {
    switch (cell) {
        CellType.Start, CellType.Floor => return try floor_tile_mesh(1, 1, Vec3.init(0.1, 0.8, 0.1)),
        CellType.End => return try floor_tile_mesh(1, 1, Vec3.init(0.1, 0.4, 0.5)),
        CellType.HorizontalWall => return try rectangle_mesh(1, 1, 0.2, Vec3.init(0.3, 0.3, 0.3)),
        CellType.VerticalWall => return try rectangle_mesh(0.2, 1, 1, Vec3.init(0.3, 0.3, 0.3)),
        CellType.HorizontalHedge => return try rectangle_mesh(1, 0.5, 0.2, Vec3.init(0.1, 0.5, 0.1)),
        CellType.VerticalHedge => return try rectangle_mesh(0.2, 0.5, 1, Vec3.init(0.1, 0.5, 0.1)),
        CellType.Platform => return try rectangle_mesh(1, 0.5, 1, Vec3.init(0.1, 0.1, 0.8)),
        CellType.RaisedPlatform => return try rectangle_mesh(1, 1, 1, Vec3.init(0.1, 0.1, 0.8)),
    }
}

fn streq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn make_grid_from_definition(def: []const u8, rows: u8) !Grid {
    grid = try Grid.init(rows, @intCast(u32, def.len) / (rows * 2));
    var si: u32 = 0;
    var index: u32 = 0;
    while (si < def.len) : (si += 2) {
        if (def[si] == '\n') {
            si -= 1;
            continue;
        }
        const s = def[si .. si + 2];

        var mesh: Mesh = undefined;
        if (streq(s, "  ")) {
            mesh = try make_mesh_from_cell_type(CellType.Floor);
        } else if (streq(s, "==")) {
            mesh = try make_mesh_from_cell_type(CellType.HorizontalWall);
        } else if (streq(s, "||")) {
            mesh = try make_mesh_from_cell_type(CellType.VerticalWall);
        } else if (streq(s, "--")) {
            mesh = try make_mesh_from_cell_type(CellType.HorizontalHedge);
        } else if (streq(s, "| ")) {
            mesh = try make_mesh_from_cell_type(CellType.VerticalHedge);
        } else if (streq(s, "TT")) {
            mesh = try make_mesh_from_cell_type(CellType.RaisedPlatform);
        } else if (streq(s, "__")) {
            mesh = try make_mesh_from_cell_type(CellType.Platform);
        } else if (streq(s, "> ")) {
            mesh = try make_mesh_from_cell_type(CellType.Start);
            grid.start = index;
        } else if (streq(s, " >")) {
            mesh = try make_mesh_from_cell_type(CellType.End);
            grid.end = index;
        } else {
            std.debug.panic("Unknown symbol: {s}", .{s});
        }
        const p = grid.point_from_index(index);
        grid.entities[index] = try new_entity(mesh, grid.world_from_point(p));
        std.debug.print("{}, {}, {}\n", .{ index, grid.entities[index].gl_buffer, grid.entities[index].mesh });
        index += 1;
    }
    return grid;
}

fn grid1() !Grid {
    const def =
        \\>       TT    ||----
        \\              ||   >
        \\--------__----||----
    ;

    return make_grid_from_definition(def, 3);
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

var meshes = std.ArrayList(Mesh).init(&gpa.allocator);
var gl_buffers = std.ArrayList(GLBuffer).init(&gpa.allocator);

const Controls = struct { move_forwards: bool, move_backwards: bool, move_left: bool, move_right: bool, dx: f32, dy: f32 };
var controls: Controls = undefined;
var camera = Camera.init(window_ratio);
var axes: Axes = undefined;
var grid: Grid = undefined;

fn normal_for_face(vertices: [*]Vec3) Vec3 {
    const v = vertices[1].sub(vertices[0]);
    const w = vertices[2].sub(vertices[0]);
    return v.cross(w).normalize();
}

fn compute_normals(vertices: []Vec3) ![]Vec3 {
    var normals = try gpa.allocator.alloc(Vec3, vertices.len);
    var i: u32 = 0;
    while (i < vertices.len) : (i += 3) {
        const n = normal_for_face(vertices.ptr + i);
        normals[i] = n;
        normals[i + 1] = n;
        normals[i + 2] = n;
    }
    return normals;
}

fn floor_tile_mesh(width: f32, depth: f32, color: Vec3) !Mesh {
    var mesh: Mesh = undefined;
    const x = width;
    const z = depth;
    mesh.vertices = try gpa.allocator.alloc(Vec3, 6);
    mesh.vertices[0] = Vec3.init(0, 0, 0);
    mesh.vertices[1] = Vec3.init(x, 0, 0);
    mesh.vertices[2] = Vec3.init(0, 0, z);
    mesh.vertices[3] = Vec3.init(0, 0, z);
    mesh.vertices[4] = Vec3.init(x, 0, 0);
    mesh.vertices[5] = Vec3.init(x, 0, z);

    mesh.normals = try compute_normals(mesh.vertices);
    mesh.color = color;
    return mesh;
}

fn rectangle_mesh(width: f32, height: f32, depth: f32, color: Vec3) !Mesh {
    const v0 = Vec3.init(0, 0, depth);
    const v1 = Vec3.init(0, 0, 0);
    const v2 = Vec3.init(0, height, depth);
    const v3 = Vec3.init(0, height, 0);
    const v4 = Vec3.init(width, 0, depth);
    const v5 = Vec3.init(width, 0, 0);
    const v6 = Vec3.init(width, height, depth);
    const v7 = Vec3.init(width, height, 0);

    var mesh: Mesh = undefined;
    mesh.vertices = try gpa.allocator.alloc(Vec3, 36);
    const faces = [_]Vec3{
        v0, v2, v1, v2, v3, v1, // left
        v1, v3, v5, v5, v3, v7, // back
        v5, v7, v6, v6, v4, v5, // right
        v4, v6, v2, v2, v0, v4, // front
        v2, v6, v3, v3, v6, v7, // top
        v0, v1, v4, v4, v1, v5,
    }; // bottom
    std.mem.copy(Vec3, mesh.vertices, &faces);
    mesh.normals = try compute_normals(mesh.vertices);
    mesh.color = color;
    return mesh;
}

fn gl_buffer_from_mesh(mesh: Mesh) !GLBuffer {
    var buf: GLBuffer = undefined;
    buf.n_vertices = @intCast(u32, mesh.vertices.len);
    buf.color = Vec3.init(1, 0, 0);
    buf.shader = try Shader.init("shaders/phong_vertex.glsl", "shaders/phong_fragment.glsl");

    var data = try gpa.allocator.alloc(Vec3, 2 * mesh.vertices.len);
    defer gpa.allocator.free(data);
    var i: u32 = 0;
    while (i < mesh.vertices.len) : (i += 1) {
        data[i * 2] = mesh.vertices[i];
        data[i * 2 + 1] = mesh.normals[i];
    }

    c.glGenVertexArrays(1, &buf.vao);
    var vbo: c.GLuint = undefined;
    c.glGenBuffers(1, &vbo);
    c.glBindVertexArray(buf.vao);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, data.len * @sizeOf(Vec3)), data.ptr, c.GL_STATIC_DRAW);
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 2 * @sizeOf(Vec3), null);
    c.glEnableVertexAttribArray(0);
    c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, 2 * @sizeOf(Vec3), @intToPtr(*c_void, @sizeOf(Vec3)));
    c.glEnableVertexAttribArray(1);

    return buf;
}

fn new_entity(mesh: Mesh, position: Vec3) !Entity {
    try meshes.append(mesh);
    const mesh_id = meshes.items.len - 1;
    try gl_buffers.append(try gl_buffer_from_mesh(mesh));
    const buf_id = gl_buffers.items.len - 1;
    return Entity{ .gl_buffer = buf_id, .mesh = mesh_id, .position = position };
}

fn render_entities(entities: []Entity) void {
    const view = camera.get_view();
    for (entities) |entity| {
        print(entity.gl_buffer);
        const buf = gl_buffers.items[entity.gl_buffer];

        // TODO: move shader out of structure, render all with same shader after grouping
        buf.shader.use();
        defer buf.shader.unuse();

        c.glBindVertexArray(buf.vao);
        defer c.glBindVertexArray(0);

        try buf.shader.set_vec3("color", buf.color);
        try buf.shader.set_mat4("model", Mat4.translate(entity.position));
        try buf.shader.set_mat4("projection", camera.projection);
        try buf.shader.set_mat4("view", view);
        // cast to i64 to make it signed (not i32, not enough bits), then truncate to c_int
        c.glDrawArrays(c.GL_TRIANGLES, 0, @truncate(c_int, @intCast(i64, buf.n_vertices)));
    }
}

fn draw_cursor() void {
    c.glPointSize(5);
    c.glBegin(c.GL_POINTS);
    c.glColor3d(1, 1, 1);
    c.glVertex3d(0, 0, 0);
    c.glEnd();
}

fn draw() void {
    c.glClearColor(0, 0, 0, 0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    axes.draw(camera);

    render_entities(grid.entities);

    draw_cursor();
}

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

const window_width = 1920;
var window_height: u32 = undefined;
const window_ratio = 16.0 / 9.0;

fn print(x: anytype) void {
    std.debug.print("{}\n", .{x});
}

fn init() !void {
    axes = try Axes.init();

    grid = try grid1();

    c.glEnable(c.GL_DEPTH_TEST);
    // c.glEnable(c.GL_BLEND);
    // c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
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
    _ = c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
    mouse_throttle = try std.time.Timer.start();
    _ = c.glfwSetCursorPosCallback(window, glfw_cursor_callback);

    try init();

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
