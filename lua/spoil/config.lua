local M = {}

M.defaults = {
  auth = {
    client_id = nil,
    auto_auth = true,
    open_browser = true,
    clipboard = true,
    port = 12676,
    scopes = {
      "playlist-read-private",
      "playlist-read-collaborative",
      "playlist-modify-public",
      "playlist-modify-private",
      "user-read-currently-playing",
      "user-read-playback-state",
      "user-modify-playback-state",
      "user-read-recently-played",
      "user-read-playback-position",
      "user-library-read",
      "user-follow-read",
      "user-top-read",
      "user-read-email",
    },
  },
  notify = {
    backend = "native",
  },
  statusline = {
    sep = " | ",
    fmt = { "artist", "title" },
    not_playing = "",
    interval = 5000,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
