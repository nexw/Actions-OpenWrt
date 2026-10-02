module("luci.controller.cellscan", package.seeall)

-- 邻区扫描（适配 NRadio C8 / MT5700M 展锐模组）
--
-- 上游（newton-miku/luci-app-cellscan）只支持移远：写 at+qscan 到 /dev/ttyUSB2
-- 再解析 +QSCAN 响应，而且模板选择里 MT5700 会落到 cellscan_null（空页）。
-- 本仓库改为：
--   * 模板选择增加 MT5700 分支
--   * 扫描改用 /usr/share/modem/mt5700-cellscan.sh（AT^MONNC 展锐邻区指令）
--   * /tmp/kpcellinfo 改为纯 CSV：mode,operator,band,earfcn,pci,rsrp,rsrq

local SCAN_SCRIPT = "/usr/share/modem/mt5700-cellscan.sh"

function index()
	local template_name = "cellscan/cellscan_null"
	local file = io.open("/tmp/modconf.conf", "r")
	if file then
		local content = file:read("*all")
		file:close()
		if content then
			if string.find(content, "MT5700") then
				template_name = "cellscan/cellscan"
			elseif string.find(content, "RM520") then
				template_name = "cellscan/cellscan"
			end
		end
	end

	entry({"admin", "modem", "cellscan"}, template(template_name), _("邻区扫描"), 80).dependent = true
	entry({"admin", "modem", "cellscan", "switch2"},  call("action_scan_all"), nil)
	entry({"admin", "modem", "cellscan", "switch5g"}, call("action_scan_5g"),  nil)
	entry({"admin", "modem", "cellscan", "switch4g"}, call("action_scan_4g"),  nil)
end

local function run_scan(rat)
	luci.http.redirect(luci.dispatcher.build_url("admin", "modem", "cellscan"))
	if rat then
		os.execute(SCAN_SCRIPT .. " " .. rat)
	else
		os.execute(SCAN_SCRIPT)
	end
end

function action_scan_all()
	if luci.http.formvalue("confirm") == "yes" then run_scan(nil) end
end

function action_scan_5g()
	if luci.http.formvalue("confirm") == "yes" then run_scan("5") end
end

function action_scan_4g()
	if luci.http.formvalue("confirm") == "yes" then run_scan("4") end
end

-- 读 /tmp/kpcellinfo（纯 CSV，见 mt5700-cellscan.sh）
function parse_results()
	local out = {}
	local f = io.open("/tmp/kpcellinfo", "r")
	if not f then
		table.insert(out, { mode = "wait for ctrl...", operator = "", band = "",
		                    earfcn = "", pci = "", rsrp = "", rsrq = "" })
		return out
	end
	for line in f:lines() do
		local mode, operator, band, earfcn, pci, rsrp, rsrq =
			line:match('^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)')
		if earfcn and earfcn ~= "" then
			table.insert(out, {
				mode = mode, operator = operator, band = band, earfcn = earfcn,
				pci = pci, rsrp = rsrp, rsrq = rsrq,
			})
		end
	end
	f:close()
	return out
end

function cellscan_run_time()
	local t = "1"
	local f = io.open("/tmp/cellscan_run_time", "r")
	if f then
		t = f:read("*all")
		io.close(f)
	end
	return t
end
