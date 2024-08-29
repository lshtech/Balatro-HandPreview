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
			G.consumeables.T.x + G.consumeables.T.w,
			G.consumeables.T.y + G.consumeables.T.h + 0.4,
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

	for size = 1, math.min(5, #filtered_cards) do
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

		-- Evaluate each combination
		for _, combo in ipairs(all_combos) do
			local hand_type, loc_disp_text, _, scoring_hand, _ = G.FUNCS.get_poker_hand_info(combo)
			local scoring_hand_hash = generate_card_hash(scoring_hand)
			unique_hands[scoring_hand_hash] = {
				hand_type = hand_type,
				loc_disp_text = loc_disp_text,
				scoring_hand = scoring_hand
			}
		end
	end

	return unique_hands
end

local function reorder_hands()
	local ranked_hands = {}
	for _,v in pairs(SMODS.PokerHands) do
		local hand = G.GAME.hands[v.key]
		print(v.key .. " | " .. tostring(HandPreview.config.hide_invisible_hands) .. " | " .. tostring(v.visible))
		if not (HandPreview.config.hide_invisible_hands == true and v.visible ~= true) and hand ~= nil then
			local chips = hand.s_chips + ((hand.level - 1) * hand.l_chips)
			local mult = hand.s_mult + ((hand.level - 1) * hand.l_mult)
			local value = chips * mult
			table.insert(ranked_hands, {v.key, value})
		end
	end

	table.sort(ranked_hands, function(a,b) return a[2] > b[2] end)

	local sorted_hands = {}
	for _,v in ipairs(ranked_hands) do
		table.insert(sorted_hands, v[1])
	end

	return sorted_hands
end

local function display_hands(unique_hands)
	local order = reorder_hands()

	local grouped_hands = {}
	local highest_card_value = nil
	for _, info in pairs(unique_hands) do
		local hand_type = info.hand_type
		local cards = {}
		for _, card in ipairs(info.scoring_hand) do
			cards[#cards + 1] = card
		end
		table.sort(cards, function(a, b) return a.base.id < b.base.id end)

		if not grouped_hands[hand_type] then
			grouped_hands[hand_type] = {}
		end

		local description = nil
		if hand_type == "High Card" or hand_type == "bunc_Spectrum" or hand_type == "bunc_Spectrum Five" or hand_type == "fibonacci_Fibonacci" and (not highest_card_value or cards[1].base.id > highest_card_value) then
			description = cards[1].base.value
			highest_card_value = cards[1].base.id
		elseif hand_type == "Pair" or hand_type == "Three of a Kind" or hand_type == "Four of a Kind" or hand_type == "Five of a Kind" then
			description = cards[1].base.value .. "s"
		elseif hand_type == "Two Pair" then
			description = cards[3].base.value .. "s & " .. cards[1].base.value .. "s"
		elseif hand_type == "Straight" or hand_type == "Straight Flush" or hand_type == "bunc_Straight Spectrum" then
			if cards[1].base.value == '2' and cards[#cards].base.value == 'Ace' then
				description = cards[#cards].base.value .. "-" .. cards[#cards - 1].base.value
			else
				description = cards[1].base.value .. "-" .. cards[#cards].base.value
			end
		elseif hand_type == "Flush" or hand_type == "Flush Five" or hand_type == "Royal Flush" or hand_type == "fibonacci_Flushonacci" then
			description = cards[1].base.suit
		elseif hand_type == "Full House" or hand_type == "bunc_Spectrum House" or hand_type == "Flush House" then
			local rank_counts = {}
			for _, card in ipairs(cards) do
				if not rank_counts[card.base.value] then rank_counts[card.base.value] = 0 end
				rank_counts[card.base.value] = rank_counts[card.base.value] + 1
			end
			local first, second = nil, nil
			for rank, count in pairs(rank_counts) do
				if count >= 3 then
					first = rank
				elseif not second or rank_counts[second] < count then
					second = rank
				end
			end
			description = first .. "s over " .. second .. "s"
		end

		if description then
			local is_duplicate = false
			for _, existing_description in ipairs(grouped_hands[hand_type]) do
				if existing_description == description then
					is_duplicate = true
					break
				end
			end

			if not is_duplicate then
				if hand_type == "High Card" then
					grouped_hands[hand_type][1] = description
				else
					grouped_hands[hand_type][#grouped_hands[hand_type] + 1] = description
				end
			end
		end
	end

	-- Output results
	HandPreview.container:remove_all_hands()
	local handCount = 0
	local maxHands = HandPreview.config.preview_count
	local includeDescriptions = HandPreview.config.include_breakdown

	for _, hand_type in ipairs(order) do
		if grouped_hands[hand_type] and next(grouped_hands[hand_type]) then
			-- Sort descriptions in value order for multiple entries in the same hand type
			table.sort(grouped_hands[hand_type], function(a, b)
				local a_high = a:match("^(.-)%s") or a
				local b_high = b:match("^(.-)%s") or b
				return a_high > b_high
			end)

			local descriptions = table.concat(grouped_hands[hand_type], ", ")
			local handInfo = G.localization.misc.poker_hands[hand_type]
			if includeDescriptions then
				handInfo = handInfo .. ": " .. descriptions
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
local orig_update = Game.update
function Game:update(dt)
	orig_update(self, dt)

	local preview_count = HandPreview.config.preview_count
	local include_facedown = HandPreview.config.include_facedown
	local include_breakdown = HandPreview.config.include_breakdown

	if HandPreview.container then
		HandPreview.container.states.visible = (self.STATE == self.STATES.SELECTING_HAND or self.STATE == self.STATES.HAND_PLAYED or self.STATE == self.STATES.DRAW_TO_HAND) and
			preview_count > 0

		if HandPreview.container.states.visible and G.hand then
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

----------------------------------------------
------------MOD CODE END----------------------
