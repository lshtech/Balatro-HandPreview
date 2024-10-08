--- STEAMODDED HEADER
--- MOD_NAME: Hand Preview
--- MOD_ID: handpreview
--- MOD_AUTHOR: [Toeler]
--- MOD_DESCRIPTION: A utility mod to list the hands that you can make. v1.0.0

----------------------------------------------
------------MOD CODE -------------------------

local balalib_mod = SMODS.Mods["balalib"]
if not balalib_mod then
	error("Hand Preview requires BalaLib mod to be installed")
end

HandPreview = SMODS.current_mod

HandPreview.config_tab = function()
	return {
		n = G.UIT.ROOT,
		config = { r = 0.1, minw = 8, align = "tm", padding = 0.2, colour = G.C.BLACK },
		nodes = {
			{
				n = G.UIT.R,
				config = {
					align = 'cm'
				},
				nodes = {
					create_option_cycle({
						id = "hand_preview_preview_count",
						label = "Preview Count",
						scale = 0.8,
						w = 1.2,
						options = { 0, 1, 2, 3, 4, 5 },
						opt_callback = "hand_preview_change_preview_count",
						current_option = (
							HandPreview.config.preview_count == 0 and 1 or
							HandPreview.config.preview_count == 1 and 2 or
							HandPreview.config.preview_count == 2 and 3 or
							HandPreview.config.preview_count == 3 and 4 or
							HandPreview.config.preview_count == 4 and 5 or
							HandPreview.config.preview_count == 5 and 6 or
							4 -- Default to 3
						)
					})
				}
			},
			{
				n = G.UIT.R,
				config = {
					align = 'cm'
				},
				nodes = {
					create_toggle({
						id = "hand_preview_include_breakdown_toggle",
						label = "Include Face-Down Cards",
						ref_table = HandPreview.config,
						ref_value = "include_facedown"
					})
				}
			},
			{
				n = G.UIT.R,
				config = {
					align = 'cm'
				},
				nodes = {
					create_toggle({
						id = "hand_preview_include_breakdown_toggle",
						label = "Include Hand Breakdown",
						ref_table = HandPreview.config,
						ref_value = "include_breakdown"
					})
				}
			},
			{
				n = G.UIT.R,
				config = {
					align = 'cm'
				},
				nodes = {
					create_toggle({
						id = "hand_preview_hide_invisible_hands_toggle",
						label = "Hide Hidden Hands",
						ref_table = HandPreview.config,
						ref_value = "hide_invisible_hands"
					})
				}
			}
		}
	}
end

G.FUNCS.hand_preview_change_preview_count = function(args)
	HandPreview.config.preview_count = args.to_val
end

HandPreviewContainer = MoveableContainer:extend()
function HandPreviewContainer:init(args)
	args.header = {
		n = G.UIT.T,
		config = {
			text = 'Possible Hands',
			scale = 0.3,
			colour = G.C.WHITE
		}
	}
	args.nodes = {
		{
			n = G.UIT.R,
			config = {
				minh = 0.1
			},
			nodes = {}
		},
		{ n = G.UIT.R, config = { id = "hand_list" } }
	}
	args.config = args.config or {}
	args.config.anchor = "Top Left"
	MoveableContainer.init(self, args)
end

function HandPreviewContainer:add_hand(hand_str)
	local list = self:get_UIE_by_ID("hand_list")
	self:add_child({
		n = G.UIT.R,
		nodes = {
			{
				n = G.UIT.T,
				config = {
					text = hand_str,
					scale = 0.3,
					colour = G.C.WHITE
				}
			},
		}
	}, list)
end

function HandPreviewContainer:remove_all_hands()
	local list = self:get_UIE_by_ID("hand_list")
	remove_all(list.children)
end

local orig_game_start_run = Game.start_run
function Game:start_run(args)
	orig_game_start_run(self, args)

	local container = HandPreviewContainer {
		T = {
			G.jokers.T.x,
			G.jokers.T.y + G.jokers.T.h + 0.8,
			0,
			0
		},
		config = {
			align = 'tr',
			offset = { x = 0, y = 0 },
			major = self
		}
	}
	HandPreview.container = container
end

local function generate_combinations(cards, combo_size, start_index, current_combo, all_combos, forced_cards)
	if #current_combo == combo_size then
		table.insert(all_combos, { unpack(current_combo) })
		return
	end

	for i = start_index, #cards do
		if not forced_cards or not forced_cards[cards[i]] then
			table.insert(current_combo, cards[i])
			generate_combinations(cards, combo_size, i + 1, current_combo, all_combos, forced_cards)
			table.remove(current_combo)
		end
	end
end

local function generate_card_hash(cards)
	local sorted_cards = { unpack(cards) }
	table.sort(sorted_cards, function(a, b) return a:get_nominal() < b:get_nominal() end)
	local card_hash = ""
	for _, card in ipairs(sorted_cards) do
		card_hash = card_hash .. card:get_nominal()
	end
	return card_hash
end

local function evaluate_combinations(cards)
	local unique_hands = {}
	local forced_cards = {}
	local forced_count = 0
	local include_facedown = HandPreview.config.include_facedown

	-- Identify forced selection cards and filter facedown cards if required
	local filtered_cards = {}
	for _, card in ipairs(cards) do
		if card.ability and card.ability.forced_selection then
			forced_cards[card] = true
			forced_count = forced_count + 1
		end
		if include_facedown or card.facing ~= 'back' then
			table.insert(filtered_cards, card)
		end
	end

	for size = 1, math.min(G.hand.config.highlighted_limit, #filtered_cards) do
		local all_combos = {}

		-- Generate initial combinations including forced cards
		if forced_count <= size then
			local initial_combo = {}
			for card, _ in pairs(forced_cards) do
				table.insert(initial_combo, card)
			end

			-- Generate remaining combinations
			generate_combinations(filtered_cards, size, 1, initial_combo, all_combos, forced_cards)
		end
		for _, combo in ipairs(all_combos) do
			local hand_type, _, _, _, _ = G.FUNCS.get_poker_hand_info(combo)
			if not unique_hands[hand_type] then
				table.insert(unique_hands, hand_type)
			end
		end
	end

	return unique_hands
end

local function reorder_hands()
	local ranked_hands = {}
	for _,v in pairs(SMODS.PokerHands) do
		local hand = G.GAME.hands[v.key]
		if not (HandPreview.config.hide_invisible_hands == true and v.visible ~= true) and hand ~= nil then
			local chips = to_big(hand.chips)
			local mult = to_big(hand.mult)
			local value = to_big(chips * mult)
			if type(value) == "table" and value.array then
				value = value.array[1]
			end
			table.insert(ranked_hands, {v.key, value, chips, mult})
		end
	end

	table.sort(ranked_hands, function(a,b) return a[2] > b[2] end)

	return ranked_hands
end

local function display_hands(unique_hands)
	local order = reorder_hands()

	local available_hands = {}
	for _, info in pairs(unique_hands) do
		local hand_type = info
		if not available_hands[hand_type] then
			available_hands[hand_type] = ""
		end
	end

	-- Output results
	HandPreview.container:remove_all_hands()
	local handCount = 0
	local maxHands = HandPreview.config.preview_count
	local includeDescriptions = HandPreview.config.include_breakdown

	for _, hand_type in ipairs(order) do
		if available_hands[hand_type[1]] then
			local handInfo = G.localization.misc.poker_hands[hand_type[1]]
			if includeDescriptions then
				handInfo = handInfo .. ": " .. number_format(hand_type[3]) .. "x" .. number_format(hand_type[4])
			end
			HandPreview.container:add_hand(handInfo)
			handCount = handCount + 1

			if handCount >= maxHands then
				break
			end
		end
	end
end

local prev_card_hash
local prev_preview_count
local prev_include_facedown
local prev_include_breakdown

local function check_hands(self)
	local preview_count = HandPreview.config.preview_count
	local include_facedown = HandPreview.config.include_facedown
	local include_breakdown = HandPreview.config.include_breakdown

	if HandPreview.container then
		HandPreview.container.states.visible = (self.STATE == self.STATES.SELECTING_HAND) and
			preview_count > 0
		HandPreview.container.states.anchor_points = "Top Left"
		if HandPreview.container.states.visible and G.hand and table_length(G.hand.cards) <= 52 then
			local card_hash = generate_card_hash(G.hand.cards)
			if card_hash ~= prev_card_hash or prev_preview_count ~= preview_count or prev_include_facedown ~= include_facedown or prev_include_breakdown ~= include_breakdown then
				prev_card_hash = card_hash
				prev_preview_count = preview_count
				prev_include_facedown = include_facedown
				prev_include_breakdown = include_breakdown

				if prev_preview_count == 0 then
					return
				end

				local all_hands = evaluate_combinations(G.hand.cards)
				display_hands(all_hands)
			end
		end
	end
end

local orig_update = Game.update
function Game:update(dt)
	orig_update(self, dt)
	check_hands(self)
end

----------------------------------------------
------------MOD CODE END----------------------
