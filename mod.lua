--- @diagnostic disable: lowercase-global, undefined-global

CKPT_MOD = {
    slots = {},
    logs = {},
    scheduled_saving_slot = nil,

    SLOTS = {
        ANTE = 'ante',
        ROUND = 'round',
    },
}

-- _RELEASE_MODE = false

-- For debugging.
if not _RELEASE_MODE then
    local orig_Game_draw = Game.draw
    --- @diagnostic disable-next-line: duplicate-set-field
    Game.draw = function (self)
        orig_Game_draw(self)

        love.graphics.push()
        love.graphics.setColor(0, 1, 1, 1)
        local line = 0
        for _, value in ipairs(CKPT_MOD.logs) do
            love.graphics.print(value, 10, 10+20*line)
            line = line+1
            for _ in string.gmatch(value, '\n') do
                line = line+1
            end
        end
        love.graphics.pop()
    end
end

function CKPT_MOD:log(msg)
    if _RELEASE_MODE then
        return
    end

    if type(msg) ~= "string" then
        msg = tostring(msg)
        return
    end
    table.insert(self.logs, 1, msg)
end

-- Main functions.
function CKPT_MOD:save_checkpoint_if_scheduled(save_run)
    local slot = self.scheduled_saving_slot
    if not slot then
        return
    end

    self.slots[slot] = save_run
    self:log('new checkpoint ('..slot..') has been saved')

    self.scheduled_saving_slot = nil
end

function CKPT_MOD:load_checkpoint(slot)
    local checkpoint = self.slots[slot]
    if not checkpoint then
        self:log('ERR: no checkpoint in slot \''..slot..'\'')
        return
    end

    local function deepcopy(v, seen)
        seen = seen or {}
        if not v then return v end
        
        if type(v) == "table" then
            local seen_t = seen[v]
            if seen_t then return seen_t end

            local new_t = {}
            seen[v] = new_t

            for k, vv in pairs(v) do
                new_t[k] = deepcopy(vv, seen)
            end

            return new_t
        else
            -- NB: there are no other ref types in save table.
            return v
        end
    end

    -- We must deep copy the save table to prevent it from being
    -- modified by the game function.
    local checkpoint_copy = deepcopy(checkpoint)
    G.FUNCS.start_run(nil, { savetext = checkpoint_copy })
end

-- Button event handlers.
G.FUNCS.load_last_round = function (e)
    CKPT_MOD:log('loading the last round')
    CKPT_MOD:load_checkpoint(CKPT_MOD.SLOTS.ROUND)
end
G.FUNCS.load_last_ante = function (e)
    CKPT_MOD:log('loading the last ante')
    CKPT_MOD:load_checkpoint(CKPT_MOD.SLOTS.ANTE)
end

-- Schedule a saving after the "cash out" event.
local orig_cash_out = G.FUNCS.cash_out
--- @diagnostic disable-next-line: duplicate-set-field
G.FUNCS.cash_out = function (e)
    CKPT_MOD:log('will cash out')
    orig_cash_out(e)
    G.E_MANAGER:add_event(Event({
        trigger = 'immediate',
        func = function ()
            CKPT_MOD:log('did cash out')
            local slot = CKPT_MOD.SLOTS.ROUND
            if G.GAME.round_resets.blind_states['Small'] == 'Upcoming' then
                -- The small blind is upcoming means we just defeated a boss
                -- blind, and the ante will go up.
                slot = CKPT_MOD.SLOTS.ANTE
            end
            CKPT_MOD.scheduled_saving_slot = slot
            return true
        end
    }))
end

-- Hook the saving function to create the checkpoint if scheduled.
local orig_save_run = save_run
function save_run()
    CKPT_MOD:log('did save run: '..debug.traceback())
    orig_save_run()
    CKPT_MOD:save_checkpoint_if_scheduled(G.ARGS.save_run)
end

-- Hook the UI code to insert our buttons to the options menu.
local orig_create_UIBox_generic_options = create_UIBox_generic_options
function create_UIBox_generic_options(args)
    local callstack = debug.traceback()
    if string.find(callstack, '\'create_UIBox_options\'') then
        local menu_contents = args.contents
        local i = 2
        if CKPT_MOD.slots[CKPT_MOD.SLOTS.ROUND] then
            local btn = UIBox_button{
                label = {'Load Last Round'},
                button = "load_last_round",
                minw = 5,
            }
            table.insert(menu_contents, i, btn)
            i = i+1
        end
        if CKPT_MOD.slots[CKPT_MOD.SLOTS.ANTE] then
            local btn = UIBox_button{
                label = {'Load Last Ante'},
                button = "load_last_ante",
                minw = 5,
            }
            table.insert(menu_contents, i, btn)
            i = i+1
        end
    end
    return orig_create_UIBox_generic_options(args)
end

CKPT_MOD:log('checkpoint mod loaded!')