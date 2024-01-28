local cfg = require("r.config").get_config()

local zathura_pid = {}

local has_dbus_send = vim.fn.executable("dbus-send") > 0 and 1 or 0

local ZathuraJobStdout = function (_, data, _)
    for _, cmd in ipairs(data) do
        if vim.startswith(cmd, "call ") then
            vim.cmd(cmd)
        end
    end
end

local StartZathuraNeovim = function (fullpath)
    local job_id = vim.fn.jobstart(
        {
            "zathura",
            "--synctex-editor-command",
            "echo 'call SyncTeX_backward(\"%{input}\", \"%{line}\")'",
            fullpath
        },
        {
            detach = true,
            -- FIXME:
            -- on_stderr = function(_, msg)
            --     ROnJobStderr(msg)
            -- end,
            on_stdout = function(_, data)
                ZathuraJobStdout(_, data, "stdout")
            end
        }
    )
    if job_id < 1 then
        vim.notify("Failed to run Zathura...", vim.log.levels.WARN)
    else
        zathura_pid[fullpath] = vim.fn.jobpid(job_id)
    end
end

local RStart_Zathura = function (fullpath)
    local fname = vim.fn.substitute(fullpath, ".*/", "", "")

    if zathura_pid[fullpath] and zathura_pid[fullpath] ~= 0 then
        -- Use the recorded pid to kill Zathura
        vim.fn.system('kill ' .. zathura_pid[fullpath])
    elseif vim.g.rplugin.has_wmctrl and has_dbus_send and vim.fn.filereadable("/proc/sys/kernel/pid_max") then
        -- Use wmctrl to check if the pdf is already open and get Zathura's PID
        -- to close the document and kill Zathura.
        local info = vim.fn.filter(vim.fn.split(vim.fn.system("wmctrl -xpl"), "\n"), 'v:val =~ "Zathura.*' .. fname .. '"')
        if #info > 0 then
            local pid = vim.fn.split(info[1])[3] + 0 -- + 0 to convert into number
            local max_pid = tonumber(vim.fn.readfile("/proc/sys/kernel/pid_max")[1])
            if pid > 0 and pid <= max_pid then
                vim.fn.system('dbus-send --print-reply --session --dest=org.pwmt.zathura.PID-' .. pid .. ' /org/pwmt/zathura org.pwmt.zathura.CloseDocument')
                vim.cmd("sleep 5m")
                vim.fn.system('kill ' .. pid)
                vim.cmd("sleep 5m")
            end
        end
    end

    vim.env.NVIMR_PORT = vim.g.rplugin.myport
    StartZathuraNeovim(fullpath)
end

local M = {}

M.open = function(fullpath)
    if cfg.openpdf == 1 then
        RStart_Zathura(fullpath)
        return
    end

    -- Time for Zathura to reload the PDF
    vim.cmd("sleep 200m")

    local fname = vim.fn.substitute(fullpath, ".*/", "", "")

    -- Check if Zathura was already opened and is still running
    if zathura_pid[fullpath] and zathura_pid[fullpath] ~= 0 then
        local zrun = vim.fn.system("ps -p " .. zathura_pid[fullpath])
        if zrun:find(zathura_pid[fullpath]) then
            if RRaiseWindow(fname) then
                return
            else
                RStart_Zathura(fullpath)
                return
            end
        else
            zathura_pid[fullpath] = 0
            RStart_Zathura(fullpath)
            return
        end
    else
        zathura_pid[fullpath] = 0
    end

    -- Check if Zathura was already running
    if RRaiseWindow(fname) == 0 then
        RStart_Zathura(fullpath)
        return
    end
end

M.SyncTeX_forward = function (tpath, ppath, texln, tryagain)
    local texname = vim.fn.substitute(tpath, ' ', '\\ ', 'g')
    local pdfname = vim.fn.substitute(ppath, ' ', '\\ ', 'g')
    local shortp = vim.fn.substitute(ppath, '.*/', '', 'g')

    if not zathura_pid[ppath] or (zathura_pid[ppath] and zathura_pid[ppath] == 0) then
        RStart_Zathura(ppath)
        vim.cmd("sleep 900m")
    end

    local result = vim.fn.system("zathura --synctex-forward=" .. texln .. ":1:" .. texname .. " --synctex-pid=" .. zathura_pid[ppath] .. " " .. pdfname)
    if vim.v.shell_error ~= 0 then
        zathura_pid[ppath] = 0
        if tryagain then
            RStart_Zathura(ppath)
            vim.cmd("sleep 900m")
            M.SyncTeX_forward(tpath, ppath, texln, false)
        else
            vim.notify(vim.fn.substitute(result, "\n", " ", "g"), vim.log.levels.WARN)
            return
        end
    end

    RRaiseWindow(shortp)
end

return M
