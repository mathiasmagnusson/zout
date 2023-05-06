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

    var state = State.init(renderer);
    while (!state.quit) {
        try loop(&state);
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
        return .{
            .renderer = renderer,
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

fn loop(state: *State) !void {
    handle_events(state);
    update(state);
    render(state);
}

var left_down = false;
var right_down = false;
fn handle_events(state: *State) void {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
        const down = event.type == c.SDL_KEYDOWN;
        switch (event.type) {
            c.SDL_QUIT => state.quit = true,
            c.SDL_KEYDOWN, c.SDL_KEYUP => switch (event.key.keysym.sym) {
                c.SDLK_LEFT => left_down = down,
                c.SDLK_RIGHT => right_down = down,
                c.SDLK_q => state.quit = true,
                else => {},
            },
            else => {},
        }
    }

    state.paddle_vel = 0;
    if (left_down) state.paddle_vel -= PADDLE_SPEED;
    if (right_down) state.paddle_vel += PADDLE_SPEED;
}

fn update(state: *State) void {
    state.ball.x += state.ball_vel.x;
    state.ball.y += state.ball_vel.y;
    state.paddle.x += state.paddle_vel;

    state.paddle.x = m.clamp(state.paddle.x, PADDLE_WIDTH / 2, WIDTH - PADDLE_WIDTH / 2);
    state.ball.x = m.clamp(state.ball.x, BALL_SIZE / 2, WIDTH - BALL_SIZE / 2);
    state.ball.y = m.clamp(state.ball.y, BALL_SIZE / 2, HEIGHT - BALL_SIZE / 2);

    if (state.ball.x + BALL_SIZE / 2 >= WIDTH)
        state.ball_vel.x = -BALL_SPEED;
    if (state.ball.x - BALL_SIZE / 2 <= 0)
        state.ball_vel.x = BALL_SPEED;
    if (state.ball.y - BALL_SIZE / 2 <= 0)
        state.ball_vel.y = BALL_SPEED;
    if (state.ball.y + BALL_SIZE / 2 >= HEIGHT)
        state.quit = true;

    if (state.paddle.x - PADDLE_WIDTH / 2 <= state.ball.x + BALL_SIZE / 2 and
        state.paddle.x + PADDLE_WIDTH / 2 >= state.ball.x - BALL_SIZE / 2 and
        state.ball.y + BALL_SIZE / 2 >= state.paddle.y - PADDLE_HEIGHT / 2)
    {
        state.ball_vel.y = -BALL_SPEED;
    }

    var destroyed: ?usize = null;
    for (state.obstacles()) |obst, i| {
        const dx = m.absInt(obst.x - state.ball.x) catch 0;
        const dy = m.absInt(obst.y - state.ball.y) catch 0;
        const overlap_x = (OBSTACLE_WIDTH + BALL_SIZE) / 2 - dx;
        const overlap_y = (OBSTACLE_HEIGHT + BALL_SIZE) / 2 - dy;
        if (overlap_x >= 0 and overlap_y >= 0) {
            if (overlap_x <= overlap_y) {
                state.ball_vel.x = -state.ball_vel.x;
                state.ball.x -= overlap_x * m.sign(obst.x - state.ball.x);
            }
            if (overlap_x >= overlap_y) {
                state.ball_vel.y = -state.ball_vel.y;
                state.ball.y -= overlap_y * m.sign(obst.y - state.ball.y);
            }
            destroyed = i;
        }
    }
    if (destroyed) |d| {
        state.obstacle_arr[d] = state.obstacle_arr[state.obstacle_count - 1];
        state.obstacle_count -= 1;
    }
}

fn render(state: *State) void {
    _ = c.SDL_SetRenderDrawColor(state.renderer, 0, 0, 0, 255);
    _ = c.SDL_RenderClear(state.renderer);

    // ball
    _ = c.SDL_SetRenderDrawColor(state.renderer, 255, 255, 255, 255);
    _ = c.SDL_RenderFillRect(state.renderer, &c.SDL_Rect{
        .x = state.ball.x - BALL_SIZE / 2,
        .y = state.ball.y - BALL_SIZE / 2,
        .w = BALL_SIZE,
        .h = BALL_SIZE,
    });

    // paddle
    _ = c.SDL_SetRenderDrawColor(state.renderer, 255, 255, 255, 255);
    _ = c.SDL_RenderFillRect(state.renderer, &c.SDL_Rect{
        .x = state.paddle.x - PADDLE_WIDTH / 2,
        .y = state.paddle.y - 5,
        .w = PADDLE_WIDTH,
        .h = PADDLE_HEIGHT,
    });

    // obstacles
    for (state.obstacles()) |obst| {
        _ = c.SDL_SetRenderDrawColor(
            state.renderer,
            @floatToInt(u8, @round((HEIGHT - @intToFloat(f32, obst.y) * 2) * 255 / HEIGHT)),
            @floatToInt(u8, @round(@intToFloat(f32, obst.x) * 255 / WIDTH)),
            @floatToInt(u8, @round((WIDTH - @intToFloat(f32, obst.x)) * 255 / WIDTH)),
            255,
        );
        _ = c.SDL_RenderFillRect(state.renderer, &c.SDL_Rect{
            .x = obst.x - OBSTACLE_WIDTH / 2,
            .y = obst.y - 5,
            .w = OBSTACLE_WIDTH,
            .h = OBSTACLE_HEIGHT,
        });
    }

    _ = c.SDL_RenderPresent(state.renderer);
}
