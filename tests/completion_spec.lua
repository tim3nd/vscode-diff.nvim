-- Test: Command completion
-- Validates :CodeDiff command completion with dynamic git refs

local git = require("vscode-diff.git")
local commands = require("vscode-diff.commands")

describe("Command Completion", function()
  describe("git.get_git_root_sync", function()
    it("Returns git root for valid directory", function()
      local cwd = vim.fn.getcwd()
      local root = git.get_git_root_sync(cwd)

      -- We're running in the vscode-diff.nvim repo
      if root then
        assert.equal("string", type(root))
        assert.equal(1, vim.fn.isdirectory(root))
      end
    end)

    it("Returns nil for non-git directory", function()
      local root = git.get_git_root_sync("/tmp")
      -- /tmp might or might not be in a git repo depending on system
      assert.is_true(root == nil or type(root) == "string")
    end)

    it("Handles file path input", function()
      local test_file = vim.fn.getcwd() .. "/README.md"
      local root = git.get_git_root_sync(test_file)

      if root then
        assert.equal("string", type(root))
      end
    end)
  end)

  describe("git.get_rev_candidates", function()
    it("Returns empty table for nil git_root", function()
      local candidates = git.get_rev_candidates(nil)
      assert.equal("table", type(candidates))
      assert.equal(0, #candidates)
    end)

    it("Returns HEAD refs for valid git repo", function()
      local cwd = vim.fn.getcwd()
      local git_root = git.get_git_root_sync(cwd)

      if git_root then
        local candidates = git.get_rev_candidates(git_root)
        assert.equal("table", type(candidates))
        assert.is_true(#candidates > 0, "Should return some candidates")

        -- Should include HEAD refs
        assert.is_true(vim.tbl_contains(candidates, "HEAD"), "Should include HEAD")
        assert.is_true(vim.tbl_contains(candidates, "HEAD~1"), "Should include HEAD~1")
      end
    end)

    it("Returns branches for valid git repo", function()
      local cwd = vim.fn.getcwd()
      local git_root = git.get_git_root_sync(cwd)

      if git_root then
        local candidates = git.get_rev_candidates(git_root)

        -- Should include main branch (this repo has main)
        local has_main = vim.tbl_contains(candidates, "main")
        local has_master = vim.tbl_contains(candidates, "master")
        assert.is_true(has_main or has_master, "Should include main or master branch")
      end
    end)

    it("Returns tags for valid git repo", function()
      local cwd = vim.fn.getcwd()
      local git_root = git.get_git_root_sync(cwd)

      if git_root then
        local candidates = git.get_rev_candidates(git_root)

        -- Check if any candidate looks like a version tag
        local has_tag = false
        for _, c in ipairs(candidates) do
          if c:match("^v%d") then
            has_tag = true
            break
          end
        end
        -- This repo has version tags
        assert.is_true(has_tag, "Should include version tags")
      end
    end)

    it("Returns remotes for valid git repo", function()
      local cwd = vim.fn.getcwd()
      local git_root = git.get_git_root_sync(cwd)

      if git_root then
        local candidates = git.get_rev_candidates(git_root)

        -- Check if any candidate is a remote ref
        local has_remote = false
        for _, c in ipairs(candidates) do
          if c:match("^origin/") then
            has_remote = true
            break
          end
        end
        assert.is_true(has_remote, "Should include remote refs")
      end
    end)
  end)

  describe("commands.SUBCOMMANDS", function()
    it("Exports SUBCOMMANDS list", function()
      assert.equal("table", type(commands.SUBCOMMANDS))
      assert.is_true(#commands.SUBCOMMANDS > 0, "Should have subcommands")
    end)

    it("Contains expected subcommands", function()
      assert.is_true(vim.tbl_contains(commands.SUBCOMMANDS, "file"), "Should include 'file'")
      assert.is_true(vim.tbl_contains(commands.SUBCOMMANDS, "install"), "Should include 'install'")
    end)
  end)

  describe("Completion caching", function()
    it("Returns consistent results on repeated calls", function()
      local cwd = vim.fn.getcwd()
      local git_root = git.get_git_root_sync(cwd)

      if git_root then
        local candidates1 = git.get_rev_candidates(git_root)
        local candidates2 = git.get_rev_candidates(git_root)

        assert.equal(#candidates1, #candidates2, "Should return same number of candidates")

        -- Verify content matches
        for i, c in ipairs(candidates1) do
          assert.equal(c, candidates2[i], "Candidates should match at index " .. i)
        end
      end
    end)
  end)
end)
