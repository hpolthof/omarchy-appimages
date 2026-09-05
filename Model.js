// Pure helpers shared by the bar widget and its panel: parsing what
// bin/appimages emits, and the strings both sides render.

var GLYPH = {
  package: "󰏖",
  refresh: "󰑐",
  play: "󰐊",
  rename: "󰑕",
  eye: "󰈈",
  eyeOff: "󰈉",
  trash: "󰆴",
  focus: "󰏌",
  folder: "󰉋"
}

// bin/appimages list emits one tab-separated row per AppImage. Tabs cannot
// occur in any field, so splitting is enough -- no quoting to unwind.
function parseList(text) {
  var rows = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.trim() === "") continue
    var parts = line.split("\t")
    if (parts.length < 10) continue
    var file = parts[2]
    rows.push({
      id: parts[0],
      name: parts[1],
      file: file,
      base: file.slice(file.lastIndexOf("/") + 1),
      icon: parts[3],
      size: Number(parts[4]) || 0,
      custom: parts[5] === "1",
      version: parts[6],
      wmclass: parts[7],
      hidden: parts[8] === "1",
      running: parts[9] === "1"
    })
  }
  return rows
}

function formatSize(bytes) {
  var value = Number(bytes) || 0
  if (value >= 1073741824) return (value / 1073741824).toFixed(1) + " GB"
  if (value >= 1048576) return Math.round(value / 1048576) + " MB"
  if (value >= 1024) return Math.round(value / 1024) + " kB"
  return value + " B"
}

function summary(rows, directory) {
  var count = rows ? rows.length : 0
  var where = directory ? " in " + directory : ""
  if (count === 0) return "No AppImages" + where
  if (count === 1) return "1 AppImage" + where
  return count + " AppImages" + where
}

function clean(text) {
  return String(text || "").trim().split("\n")[0]
}

// The line under a name: what the file is, plus any state worth flagging.
function detailLine(row) {
  var parts = [row.base, formatSize(row.size)]
  if (row.version) parts.push("v" + row.version)
  if (row.custom) parts.push("renamed")
  if (row.hidden) parts.push("hidden")
  // Running is deliberately absent: the row's first button already says so,
  // in the accent colour and with a focus glyph instead of a play one.
  return parts.join(" · ")
}
