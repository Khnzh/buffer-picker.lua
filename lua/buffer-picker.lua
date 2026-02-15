local M = {}

-- Configuration
local config = {
	height = 15,
	width = 50,
	border = "rounded",
	highlight_selected = true,
	selected_highlight = "Visual",
	show_buffer_numbers = true,
	show_file_icons = false, -- Requires nvim-web-devicons
	mappings = {
		close = { "q", "<Esc>" },
		select = "<CR>",
		delete = "d",
		next_buffer = "j",
		prev_buffer = "k",
	},
}

-- State
local picker_bufnr = nil
local picker_winid = nil
local buffers_data = {}

-- Setup function
function M.setup(user_config)
	if user_config then
		config = vim.tbl_deep_extend("force", config, user_config)
	end
end

-- Get all buffers
local function get_buffers()
	buffers_data = {}
	local buffers = vim.api.nvim_list_bufs()

	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			local name = vim.api.nvim_buf_get_name(buf)
			-- local is_listed = true
			local is_listed = vim.api.nvim_get_option_value("buflisted", { buf = buf })
			local modified = vim.api.nvim_buf_get_option(buf, "modified")
			local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
			local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
			local line_count = vim.api.nvim_buf_line_count(buf)
			local current = buf == vim.api.nvim_get_current_buf()

			if (name ~= "" or buftype ~= "") and is_listed == true then
				table.insert(buffers_data, {
					bufnr = buf,
					name = name,
					modified = modified,
					buftype = buftype,
					filetype = filetype,
					line_count = line_count,
					listed = is_listed,
					current = current,
				})
			end
		end
	end

	return buffers_data
end

-- Format buffer line
local function format_buffer_line(buf_info, idx)
	local line = ""

	if config.show_buffer_numbers then
		line = string.format("%3d ", idx)
	end

	local status = buf_info.modified and "[+] " or "    "

	-- Get filename
	local filename = buf_info.name
	if filename == "" then
		if buf_info.buftype == "help" then
			filename = "[Help]"
		elseif buf_info.buftype == "terminal" then
			filename = "[Terminal]"
		elseif buf_info.buftype == "quickfix" then
			filename = "[Quickfix]"
		elseif buf_info.buftype == "nofile" then
			filename = "[Scratch]"
		else
			filename = "[No Name]"
		end
	else
		filename = vim.fn.fnamemodify(filename, ":t")
	end

	-- Add filetype if no name
	if buf_info.name == "" and buf_info.filetype ~= "" then
		filename = filename .. " (" .. buf_info.filetype .. ")"
	end

	line = line .. status .. filename

	-- Show full path in last column if space permits
	if buf_info.name ~= "" then
		local path = vim.fn.fnamemodify(buf_info.name, ":h")
		if path ~= "." then
			line = line .. string.format("  [%s]", path)
		end
	end

	return line
end

-- Create picker window
function M.open()
	-- Close if already open
	if picker_winid and vim.api.nvim_win_is_valid(picker_winid) then
		vim.api.nvim_win_close(picker_winid, true)
	end

	-- Get buffers
	local buffers = get_buffers()
	if #buffers == 0 then
		vim.notify("No buffers available", vim.log.levels.WARN)
		return
	end

	-- Create buffer for picker
	picker_bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(picker_bufnr, "buffer-picker")
	vim.api.nvim_buf_set_option(picker_bufnr, "filetype", "buffer-picker")
	vim.api.nvim_buf_set_option(picker_bufnr, "buftype", "nofile")
	vim.api.nvim_buf_set_option(picker_bufnr, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(picker_bufnr, "swapfile", false)

	-- Prepare content
	local lines = {}
	for i, buf in ipairs(buffers) do
		table.insert(lines, format_buffer_line(buf, i))
	end

	vim.api.nvim_buf_set_lines(picker_bufnr, 0, -1, false, lines)

	-- Set keymaps
	local keymaps = config.mappings

	vim.api.nvim_buf_set_keymap(picker_bufnr, "n", keymaps.select, "", {
		callback = function()
			M.select_buffer()
		end,
		noremap = true,
		silent = true,
		nowait = true,
	})

	vim.api.nvim_buf_set_keymap(picker_bufnr, "n", keymaps.close[1], "", {
		callback = function()
			M.close()
		end,
		noremap = true,
		silent = true,
		nowait = true,
	})

	vim.api.nvim_buf_set_keymap(picker_bufnr, "n", keymaps.close[2], "", {
		callback = function()
			M.close()
		end,
		noremap = true,
		silent = true,
		nowait = true,
	})

	vim.api.nvim_buf_set_keymap(picker_bufnr, "n", keymaps.delete, "", {
		callback = function()
			local count = vim.v.count1 -- Gets the count (defaults to 1 if no count)
			M.delete_buffers_in_range(count)
		end,
		noremap = true,
		silent = true,
		nowait = true,
	})

	-- Navigation mappings
	if keymaps.next_buffer then
		vim.api.nvim_buf_set_keymap(picker_bufnr, "n", keymaps.next_buffer, "j", {
			noremap = true,
			silent = true,
		})
	end

	if keymaps.prev_buffer then
		vim.api.nvim_buf_set_keymap(picker_bufnr, "n", keymaps.prev_buffer, "k", {
			noremap = true,
			silent = true,
		})
	end

	-- Calculate window position (centered)
	local width = config.width
	local height = math.min(#buffers + 2, config.height)
	local ui = vim.api.nvim_list_uis()[1]
	local row = math.floor((ui.height - height) / 2)
	local col = math.floor((ui.width - width) / 2)

	-- Create window
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = config.border,
		focusable = true,
	}

	picker_winid = vim.api.nvim_open_win(picker_bufnr, true, win_opts)

	-- Window options
	vim.api.nvim_win_set_option(picker_winid, "cursorline", true)
	vim.api.nvim_win_set_option(picker_winid, "winhighlight", "NormalFloat:Normal,FloatBorder:FloatBorder")

	-- Autocommand to close on buffer delete
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = picker_bufnr,
		once = true,
		callback = function()
			picker_bufnr = nil
			picker_winid = nil
		end,
	})

	-- Highlight current buffer
	M.highlight_current_buffer()
end

-- Highlight the current buffer in the picker
function M.highlight_current_buffer()
	if not picker_winid or not vim.api.nvim_win_is_valid(picker_winid) then
		return
	end

	local current_buf = vim.api.nvim_get_current_buf()
	for i, buf_info in ipairs(buffers_data) do
		if buf_info.current then
			vim.api.nvim_win_set_cursor(picker_winid, { i, 0 })

			if config.highlight_selected then
				-- Clear previous highlight
				vim.api.nvim_buf_clear_namespace(picker_bufnr, -1, 0, -1)

				-- Add highlight for selected line
				local ns = vim.api.nvim_create_namespace("buffer_picker")
				vim.api.nvim_buf_add_highlight(picker_bufnr, ns, config.selected_highlight, i - 1, 0, -1)
			end
			break
		end
	end
end

-- Select buffer under cursor
function M.select_buffer()
	if not picker_winid or not vim.api.nvim_win_is_valid(picker_winid) then
		return
	end

	local cursor_pos = vim.api.nvim_win_get_cursor(picker_winid)
	local line_num = cursor_pos[1]

	if line_num > 0 and line_num <= #buffers_data then
		local selected_buf = buffers_data[line_num].bufnr

		-- Close picker first
		M.close()

		-- Switch to selected buffer
		if vim.api.nvim_buf_is_valid(selected_buf) then
			vim.api.nvim_set_current_buf(selected_buf)
		else
			vim.notify("Buffer no longer valid", vim.log.levels.ERROR)
		end
	end
end

-- Delete buffer under cursor
function M.delete_buffers_in_range(count)
	if not picker_winid or not vim.api.nvim_win_is_valid(picker_winid) then
		return
	end

	local cursor_pos = vim.api.nvim_win_get_cursor(picker_winid)
	local start_line = cursor_pos[1]
	local end_line = math.min(start_line + count - 1, #buffers_data)

	-- Delete buffers in reverse order (to avoid line number shifting)
	for line = end_line, start_line, -1 do
		if line > 0 and line <= #buffers_data then
			local selected_buf = buffers_data[line].bufnr

			-- Skip modified buffers
			if vim.api.nvim_buf_get_option(selected_buf, "modified") then
				vim.notify(
					string.format("Buffer %s has unsaved changes. Skipped.", vim.api.nvim_buf_get_name(selected_buf)),
					vim.log.levels.WARN
				)
			else
				vim.api.nvim_buf_delete(selected_buf, { force = true })
			end
		end
	end

	-- Refresh the picker
	M.open()
end

-- Close picker window
function M.close()
	if picker_winid and vim.api.nvim_win_is_valid(picker_winid) then
		vim.api.nvim_win_close(picker_winid, true)
	end
	picker_bufnr = nil
	picker_winid = nil
end

-- Toggle picker window
function M.toggle()
	if picker_winid and vim.api.nvim_win_is_valid(picker_winid) then
		M.close()
	else
		M.open()
	end
end

-- Command to open buffer picker
vim.api.nvim_create_user_command("BufferPicker", M.open, {
	desc = "Open buffer picker window",
})

-- Default keybinding (optional)
vim.keymap.set("n", "<leader>bp", M.open, { desc = "Open buffer picker" })

return M
