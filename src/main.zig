const std = @import("std");
const c = @cImport({
    @cInclude("SDL.h");
});

const Vec2 = @Vector(2, i32);

const WIDTH = 500;
const HEIGHT = 800;
const BALL_SPEED = 3;
const BALL_SIZE = 10;
const PADDLE_SPEED = 3;
const PADDLE_WIDTH = 100;
const PADDLE_HEIGHT = 10;

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

    while (!quit) {
        try loop(renderer);
    }
}

fn sdlErr(return_value: anytype) !void {
    if (return_value == 0) return;
    std.log.info("SDL error: {s}", .{c.SDL_GetError()});
    return error.SDLError;
}

var quit = false;

var ball = Vec2{ WIDTH / 2, HEIGHT - 25 };
var ball_vel = Vec2{ BALL_SPEED, -BALL_SPEED };
var paddle = Vec2{ WIDTH / 2, HEIGHT - 10 };
var paddle_vel: i32 = 0;

fn loop(renderer: *c.SDL_Renderer) !void {
    handle_events();
    update();
    render(renderer);
}

fn handle_events() void {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
        switch (event.type) {
            c.SDL_QUIT => quit = true,
            c.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                c.SDLK_LEFT => paddle_vel = -PADDLE_SPEED,
                c.SDLK_RIGHT => paddle_vel = PADDLE_SPEED,
                c.SDLK_q => quit = true,
                else => {},
            },
            c.SDL_KEYUP => switch (event.key.keysym.sym) {
                c.SDLK_LEFT, c.SDLK_RIGHT => paddle_vel = 0,
                else => {},
            },
            else => {},
        }
    }
}

fn update() void {
    paddle[0] += paddle_vel;
    ball += ball_vel;
    if (ball[0] >= WIDTH) {
        ball[0] = WIDTH;
        ball_vel[0] = -BALL_SPEED;
    }
    if (ball[0] <= 0) {
        ball[0] = 0;
        ball_vel[0] = BALL_SPEED;
    }
    if (ball[1] < 0) {
        ball[1] = 0;
        ball_vel[1] = BALL_SPEED;
    }
    if (ball[1] > HEIGHT) quit = true;

    if (paddle[0] - PADDLE_WIDTH / 2 <= ball[0] + BALL_SIZE / 2 and paddle[0] + PADDLE_WIDTH / 2 >= ball[0] - BALL_SIZE / 2 and ball[1] + BALL_SIZE / 2 >= paddle[1] - PADDLE_HEIGHT / 2) {
        ball_vel[1] = -BALL_SPEED;
    }
}

fn render(renderer: *c.SDL_Renderer) void {
    _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    _ = c.SDL_RenderClear(renderer);

    // Draw ball
    _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
    _ = c.SDL_RenderFillRect(renderer, &c.SDL_Rect{
        .x = ball[0] - BALL_SIZE / 2,
        .y = ball[1] - BALL_SIZE / 2,
        .w = BALL_SIZE,
        .h = BALL_SIZE,
    });
    // Draw paddle
    _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
    _ = c.SDL_RenderFillRect(renderer, &c.SDL_Rect{
        .x = paddle[0] - PADDLE_WIDTH / 2,
        .y = paddle[1] - 5,
        .w = PADDLE_WIDTH,
        .h = PADDLE_HEIGHT,
    });

    _ = c.SDL_RenderPresent(renderer);
}
