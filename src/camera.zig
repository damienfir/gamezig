const math = @import("math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

pub const Camera = struct {
    projection: Mat4,
    position: Vec3,
    direction: Vec3,
    up: Vec3,
    speed: f32,

    pub fn init(ratio: f32) Camera {
        return Camera{
            .projection = Mat4.perpective(0.1, 100.0, 0.05, 0.05 / ratio),
            .position = Vec3.init(1, 1, 3),
            .direction = Vec3.init(0, 0, -1).normalize(),
            .up = Vec3.init(0, 1, 0),
            .speed = 5,
        };
    }

    pub fn get_view(self: Camera) Mat4 {
        return Mat4.lookat(self.position, self.position.add(self.direction), self.up);
    }

    pub fn get_horizontal_vector(self: Camera) Vec3 {
        return self.direction.cross(self.up).normalize();
    }

    pub fn rotate_direction(self: *Camera, dx: f32, dy: f32) void {
        var dir = self.direction.add(self.direction.cross(self.up).normalize().scale(dx * 0.002));
        dir = dir.add(self.up.scale(dy * 0.002));
        self.direction = dir.normalize();
    }
};
