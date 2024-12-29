if vim.fn.has'nvim-0.10' == 0 then
  vim.cmd'command! Notes lua require"notes".toggle()'
else
  vim.api.nvim_create_user_command('Notes', function ()
    require'notes'.toggle()
  end, {})
end

