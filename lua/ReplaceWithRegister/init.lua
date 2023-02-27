-- ReplaceWithRegister.vim: Replace text with the contents of a register.
--
-- DEPENDENCIES:
--   - repeat.vim (vimscript #2136) autoload script (optional)
--   - visualrepeat.vim (vimscript #3848) autoload script (optional)
--   - visualrepeat/reapply.vim autoload script (optional)
--
-- Copyright: (C) 2011-2014 Ingo Karkat
--   The VIM LICENSE applies to this script; see ':help copyright'.
--
-- Maintainer:	Ingo Karkat <ingo@karkat.de>
--
-- REVISION	DATE		REMARKS
--   1.42.010	27-Jun-2014	BUG: Off-by-one error in previously introduced
--				s:IsOnOrAfter(); actually need to use s:IsAfter().
--   1.41.009	28-May-2014	Also handle empty exclusive selection and empty
--				text object (e.g. gri" on "").
--   1.40.008	18-Apr-2013	Add ReplaceWithRegister#VisualMode() wrapper
--				around visualrepeat#reapply#VisualMode().
--   1.32.007	21-Mar-2013	Avoid changing the jumplist.
--   1.32.006	28-Dec-2012	Minor: Correct lnum for no-modifiable buffer
--				check.
--   1.30.005	06-Dec-2011	Retire visualrepeat#set_also(); use
--				visualrepeat#set() everywhere.
--   1.30.004	21-Oct-2011	Employ repeat.vim to have the expression
--				re-evaluated on repetition of the
--				operator-pending mapping.
--   1.30.003	30-Sep-2011	Avoid clobbering of expression register so that
--				a command repeat is able to re-evaluate the
--				expression.
--				Undo parallel <Plug>ReplaceWithRegisterRepeat...
--				mappings, as this is now handled by the enhanced
--				repeat.vim plugin.
--   1.30.002	27-Sep-2011	Adaptations for blockwise replace:
--				- If the register contains just a single line,
--				  temporarily duplicate the line to match the
--				  height of the blockwise selection.
--				- If the register contains multiple lines, paste
--				  as blockwise.
--   1.30.001	24-Sep-2011	Moved functions from plugin to separate autoload
--				script.
--				file creation

local register = nil
local M = {}

function M.SetRegister()
    register = vim.v.register
end
function M.IsExprReg()
    return register == '='
end

-- Note: Could use ingo#pos#IsOnOrAfter(), but avoid dependency to ingo-library
-- for now.
local function IsAfter( posA, posB )
    return (posA[1] > posB[1] or posA[1] == posB[1] and posA[2] > posB[2])
end

local function CorrectForRegtype( type, new_register, regType, pasteText )
    if type == 'visual' and vim.fn.visualmode() == [[\<C-v>]] or type[0] == [[\<C-v>]] then
	-- Adaptations for blockwise replace.
	local pasteLnum = vim.fn.len(vim.fn.split(pasteText, "\n"))
	if regType ==# 'v' or regType ==# 'V' and pasteLnum == 1 then
	    -- If the register contains just a single line, temporarily duplicate
	    -- the line to match the height of the blockwise selection.
	    local height = vim.fn.line("'>") - vim.fn.line("'<") + 1
	    if height > 1 then
			vim.fn.setreg(new_register, vim.fn.join(vim.fn["repeat"](vim.fn.split(pasteText, "\n"), height), "\n"), [[\<C-v>]])
			return 1
	    end
	elseif regType == 'V' and pasteLnum > 1 then
	    -- If the register contains multiple lines, paste as blockwise.
	    vim.fn.setreg(new_register, '', [[a\<C-v>]])
	    return 1
	end
    elseif regType == 'V' and pasteText:match("\n$") then
	-- Our custom operator is characterwise, even in the
	-- ReplaceWithRegisterLine variant, in order to be able to replace less
	-- than entire lines (i.e. characterwise yanks).
	-- So there's a mismatch when the replacement text is a linewise yank,
	-- and the replacement would put an additional newline to the end.
	-- To fix that, we temporarily remove the trailing newline character from
	-- the register contents and set the register type to characterwise yank.
	vim.fn.setreg(new_register, vim.fn.strpart(pasteText, 0, vim.fn.len(pasteText) - 1), 'v')

	return 1
    end

    return 0
end
local function ReplaceWithRegister( type )
    -- With a put in visual mode, the selected text will be replaced with the
    -- contents of the register. This works better than first deleting the
    -- selection into the black-hole register and then doing the insert; as
    -- "d" + "i/a" has issues at the end-of-the line (especially with blockwise
    -- selections, where "v_o" can put the cursor at either end), and the "c"
    -- commands has issues with multiple insertion on blockwise selection and
    -- autoindenting.
    -- With a put in visual mode, the previously selected text is put in the
    -- unnamed register, so we need to save and restore that.
    local save_clipboard = vim.o.clipboard
    vim.o.clipboard = "" -- Avoid clobbering the selection and clipboard registers.
    local save_reg = vim.fn.getreg('"')
    local save_regmode = vim.fn.getregtype('"')

    -- Note: Must not use ""p; this somehow replaces the selection with itself?!
    local pasteRegister = (register == '"' and '' or '"' .. register)
    if register == '=' then
	-- Cannot evaluate the expression register within a function; unscoped
	-- variables do not refer to the global scope. Therefore, evaluation
	-- happened earlier in the mappings.
	-- To get the expression result into the buffer, we use the unnamed
	-- register; this will be restored, anyway.
	vim.fn.setreg('"', vim.g.ReplaceWithRegister_expr)
	CorrectForRegtype(type, '"', vim.fn.getregtype('"'), vim.g.ReplaceWithRegister_expr)
	-- Must not clean up the global temp variable to allow command
	-- repetition.
	--unlet vim.g.ReplaceWithRegister_expr
	pasteRegister = ''
    end
    local save_selection
    pcall( function()
	if type == 'visual' then
	    if vim.o.selection == 'exclusive' and vim.fn.getpos("'<") == vim.fn.getpos("'>") then
		-- In case of an empty selection, just paste before the cursor
		-- position; reestablishing the empty selection would override
		-- the current character, a peculiarity of how selections work.
		vim.cmd('normal! ' .. pasteRegister .. 'P')
	    else
		vim.cmd('normal! gv' .. pasteRegister .. 'p')
	    end
	else
	    if IsAfter(vim.fn.getpos("'["), vim.fn.getpos("']")) then
		vim.cmd('normal! ' .. pasteRegister .. 'P')
	    else
		-- Note: Need to use an "inclusive" selection to make `] include
		-- the last moved-over character.
		save_selection = vim.o.selection
		vim.o.selection="inclusive"
		pcall(vim.cmd, 'normal! g`[' .. (type == 'line' and 'V' or 'v') .. 'g`]' .. pasteRegister .. 'p')
		vim.o.selection = save_selection
	    end
	end
    end)
    vim.fn.setreg('"', save_reg, save_regmode)
    vim.o.clipboard = save_clipboard
end
function M.Operator( type, ... )
    local pasteText = vim.fn.getreg(register, 1) -- Expression evaluation inside function context may cause errors, therefore get unevaluated expression when s:register ==# '='.
    local regType = vim.fn.getregtype(register)
    local isCorrected = CorrectForRegtype(type, register, regType, pasteText)
    pcall(ReplaceWithRegister, type)
    if isCorrected then
	-- Undo the temporary change of the register.
	-- Note: This doesn't cause trouble for the read-only registers :, .,
	-- %, # and =, because their regtype is always 'v'.
	vim.fn.setreg(register, pasteText, regType)
    end

    if 0 then
	pcall(vim.fn["repeat#set"], 1)
    elseif register == '=' then
	-- Employ repeat.vim to have the expression re-evaluated on repetition of
	-- the operator-pending mapping.
	pcall(vim.fn["repeat#set"], [[\<Plug>ReplaceWithRegisterExpressionSpecial]])
    end
    pcall(vim.fn["visualrepeat#set"], [[\<Plug>ReplaceWithRegisterVisual]])
end
function M.OperatorExpression()
    M.SetRegister()
    vim.o.opfunc="v:lua.require'ReplaceWithRegister'.Operator"

    local keys = 'g@'

	--    if not &l:modifiable or &l:readonly then
	-- -- Probe for "Cannot make changes" error and readonly warning via a no-op
	-- -- dummy modification.
	-- -- In the case of a nomodifiable buffer, Vim will abort the normal mode
	-- -- command chain, discard the g@, and thus not invoke the operatorfunc.
	-- keys = ":call setline('.', vim.fn.getline('.'))\<CR>" .. keys
	--    end

    if vim.v.register == '=' then
	-- Must evaluate the expression register outside of a function.
	keys = [[:let vim.g.ReplaceWithRegister_expr = vim.fn.getreg('=')\<CR>]] .. keys
    end

    return keys
end

function M.VisualMode()
    local ok, keys = pcall(vim.fn["visualrepeat#reapply#VisualMode"], 0)
    if ok then return keys end
    return [[1v\<Esc>]]
end

return M
-- vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
