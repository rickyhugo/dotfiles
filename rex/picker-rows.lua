local directory = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*/)") or "./"
package.path = directory .. "?.lua;" .. package.path
require("project-picker").rows(rex.args)
