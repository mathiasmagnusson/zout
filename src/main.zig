const std = @import("std");
const c = @cImport({
    @cInclude("SDL.h");
});
const m = std.math;

const Vec2 = struct { x: i32, y: i32 };

const WIDTH = 500;
const HEIGHT = 800;

const BALL_SPEED = 4;
const BALL_SIZE = 10;

const PADDLE_SPEED = 3;
const PADDLE_WIDTH = 100;
const PADDLE_HEIGHT = 10;

const OBSTACLE_WIDTH = 50;
const OBSTACLE_HEIGHT = 15;
const OBSTACLES_C = 6;
const OBSTACLES_R = 10;

pub fn main() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        std.log.info("SDL_Init failed: {s}", .{c.SDL_GetError()});
        return error.SDLInit;
    }
    defer c.SDL_Quit();

    var window = c.SDL_CreateWindow(
        "Zout!",
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        WIDTH,
        HEIGHT,
        0,
    ) orelse {
        std.log.info("SDL_CreateWindow failed: {s}", .{c.SDL_GetError()});
        return error.CreateWindow;
    };
    defer c.SDL_DestroyWindow(window);

    var renderer = c.SDL_CreateRenderer(window, -1, 0) orelse {
        std.log.info("SDL_CreateRenderer failed: {s}", .{c.SDL_GetError()});
        return error.CreateRenderer;
    };
    defer c.SDL_DestroyRenderer(renderer);
    try sdlErr(c.SDL_RenderSetVSync(renderer, 1));

    var s = State.init(renderer);
    while (!s.quit) {
        try loop(&s);
    }
}

fn sdlErr(return_value: anytype) !void {
    if (return_value == 0) return;
    std.log.info("SDL error: {s}", .{c.SDL_GetError()});
    return error.SDLError;
}

const State = struct {
    renderer: *c.SDL_Renderer,

    quit: bool = false,

    ball: Vec2 = Vec2{ .x = WIDTH / 2, .y = HEIGHT - 25 },
    ball_vel: Vec2 = Vec2{ .x = BALL_SPEED, .y = -BALL_SPEED },

    paddle: Vec2 = Vec2{ .x = WIDTH / 2, .y = HEIGHT - 10 },
    paddle_vel: i32 = 0,

    obstacle_arr: [OBSTACLES_C * OBSTACLES_R]Vec2 = initial_obstacles(),
    obstacle_count: usize = OBSTACLES_C * OBSTACLES_R,

    fn init(renderer: *c.SDL_Renderer) @This() {
        var prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp()));
        var rand = prng.random();
        var ball_vel_x = rand.intRangeAtMost(i32, -BALL_SPEED, BALL_SPEED);
        if (ball_vel_x == 0) ball_vel_x = 1;
        return .{
            .renderer = renderer,
            .ball_vel = Vec2{
                .x = ball_vel_x,
                .y = BALL_SPEED,
            },
        };
    }

    fn obstacles(self: *@This()) []Vec2 {
        return self.obstacle_arr[0..self.obstacle_count];
    }
};

fn initial_obstacles() [OBSTACLES_C * OBSTACLES_R]Vec2 {
    var res = [_]Vec2{undefined} ** (OBSTACLES_C * OBSTACLES_R);
    var y: usize = 0;
    while (y < OBSTACLES_R) : (y += 1) {
        var x: usize = 0;
        while (x < OBSTACLES_C) : (x += 1) {
            res[y * OBSTACLES_C + x] = .{
                .x = @intCast(i32, (x + 1) * WIDTH / (OBSTACLES_C + 1)),
                .y = @intCast(i32, 20 + y * (OBSTACLE_HEIGHT + 15)),
            };
        }
    }
    return res;
}

fn loop(s: *State) !void {
    handle_events(s);
    update(s);
    render(s);
}

var left_down = false;
var right_down = false;
fn handle_events(s: *State) void {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
        const down = event.type == c.SDL_KEYDOWN;
        switch (event.type) {
            c.SDL_QUIT => s.quit = true,
            c.SDL_KEYDOWN, c.SDL_KEYUP => switch (event.key.keysym.sym) {
                c.SDLK_LEFT => left_down = down,
                c.SDLK_RIGHT => right_down = down,
                c.SDLK_q => s.quit = true,
                else => {},
            },
            else => {},
        }
    }

    s.paddle_vel = 0;
    if (left_down) s.paddle_vel -= PADDLE_SPEED;
    if (right_down) s.paddle_vel += PADDLE_SPEED;
}

fn update(s: *State) void {
    s.ball.x += s.ball_vel.x;
    s.ball.y += s.ball_vel.y;
    s.paddle.x += s.paddle_vel;

    s.paddle.x = m.clamp(s.paddle.x, PADDLE_WIDTH / 2, WIDTH - PADDLE_WIDTH / 2);
    s.ball.x = m.clamp(s.ball.x, BALL_SIZE / 2, WIDTH - BALL_SIZE / 2);
    s.ball.y = m.clamp(s.ball.y, BALL_SIZE / 2, HEIGHT - BALL_SIZE / 2);

    if (s.ball.x - BALL_SIZE / 2 <= 0)
        s.ball_vel.x = m.absInt(s.ball_vel.x) catch 1;
    if (s.ball.x + BALL_SIZE / 2 >= WIDTH)
        s.ball_vel.x = -(m.absInt(s.ball_vel.x) catch 1);
    if (s.ball.y - BALL_SIZE / 2 <= 0)
        s.ball_vel.y = BALL_SPEED;
    if (s.ball.y + BALL_SIZE / 2 >= HEIGHT)
        s.quit = true;

    if (s.paddle.x - PADDLE_WIDTH / 2 <= s.ball.x + BALL_SIZE / 2 and
        s.paddle.x + PADDLE_WIDTH / 2 >= s.ball.x - BALL_SIZE / 2 and
        s.ball.y + BALL_SIZE / 2 >= s.paddle.y - PADDLE_HEIGHT / 2)
    {
        s.ball_vel.y = -BALL_SPEED;

        s.ball_vel.x += @divTrunc(s.paddle_vel, PADDLE_SPEED) * 2;
        s.ball_vel.x += @divTrunc((s.ball.x - s.paddle.x) * BALL_SPEED, PADDLE_WIDTH / 2);
        s.ball_vel.x = m.clamp(s.ball_vel.x, -BALL_SPEED * 2, BALL_SPEED * 2);
    }

    var destroyed: ?usize = null;
    for (s.obstacles()) |obst, i| {
        const dx = m.absInt(obst.x - s.ball.x) catch 0;
        const dy = m.absInt(obst.y - s.ball.y) catch 0;
        const overlap_x = (OBSTACLE_WIDTH + BALL_SIZE) / 2 - dx;
        const overlap_y = (OBSTACLE_HEIGHT + BALL_SIZE) / 2 - dy;
        if (overlap_x >= 0 and overlap_y >= 0) {
            if (overlap_x <= overlap_y) {
                s.ball_vel.x = -s.ball_vel.x;
                s.ball.x -= overlap_x * m.sign(obst.x - s.ball.x);
            }
            if (overlap_x >= overlap_y) {
                s.ball_vel.y = -s.ball_vel.y;
                s.ball.y -= overlap_y * m.sign(obst.y - s.ball.y);
            }
            destroyed = i;
        }
    }
    if (destroyed) |d| {
        s.obstacle_arr[d] = s.obstacle_arr[s.obstacle_count - 1];
        s.obstacle_count -= 1;
    }
}

fn render(s: *State) void {
    _ = c.SDL_SetRenderDrawColor(s.renderer, 0, 0, 0, 255);
    _ = c.SDL_RenderClear(s.renderer);

    // ball
    _ = c.SDL_SetRenderDrawColor(s.renderer, 255, 255, 255, 255);
    _ = c.SDL_RenderFillRect(s.renderer, &c.SDL_Rect{
        .x = s.ball.x - BALL_SIZE / 2,
        .y = s.ball.y - BALL_SIZE / 2,
        .w = BALL_SIZE,
        .h = BALL_SIZE,
    });

    // paddle
    _ = c.SDL_SetRenderDrawColor(s.renderer, 255, 255, 255, 255);
    _ = c.SDL_RenderFillRect(s.renderer, &c.SDL_Rect{
        .x = s.paddle.x - PADDLE_WIDTH / 2,
        .y = s.paddle.y - 5,
        .w = PADDLE_WIDTH,
        .h = PADDLE_HEIGHT,
    });

    // obstacles
    for (s.obstacles()) |obst| {
        _ = c.SDL_SetRenderDrawColor(
            s.renderer,
            @floatToInt(u8, @round((HEIGHT - @intToFloat(f32, obst.y) * 2) * 255 / HEIGHT)),
            @floatToInt(u8, @round(@intToFloat(f32, obst.x) * 255 / WIDTH)),
            @floatToInt(u8, @round((WIDTH - @intToFloat(f32, obst.x)) * 255 / WIDTH)),
            255,
        );
        _ = c.SDL_RenderFillRect(s.renderer, &c.SDL_Rect{
            .x = obst.x - OBSTACLE_WIDTH / 2,
            .y = obst.y - 5,
            .w = OBSTACLE_WIDTH,
            .h = OBSTACLE_HEIGHT,
        });
    }

    _ = c.SDL_RenderPresent(s.renderer);
}
