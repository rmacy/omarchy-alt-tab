.pragma library

function historyRank(client) {
  var rank = Number(client && client.focusHistoryID)
  return isFinite(rank) && rank >= 0 ? rank : 2147483647
}

function switchableClients(clients, monitorId) {
  var source = Array.isArray(clients) ? clients : []
  var wantedMonitor = String(monitorId)
  var result = []

  for (var i = 0; i < source.length; i++) {
    var client = source[i]
    if (!client || !client.address) continue
    if (client.mapped === false || client.acceptsInput === false) continue
    if (String(client.monitor) !== wantedMonitor) continue
    result.push(client)
  }

  result.sort(function(a, b) {
    var byHistory = historyRank(a) - historyRank(b)
    if (byHistory !== 0) return byHistory
    var aStable = String(a.stableId || a.address || "")
    var bStable = String(b.stableId || b.address || "")
    return aStable < bStable ? -1 : (aStable > bStable ? 1 : 0)
  })
  return result
}

function initialIndex(direction, count) {
  var size = Math.max(0, Number(count) || 0)
  if (size <= 1) return size - 1
  return Number(direction) < 0 ? size - 1 : 1
}

function nextIndex(index, delta, count) {
  var size = Math.max(0, Number(count) || 0)
  if (size === 0) return -1
  var current = Number(index)
  if (!isFinite(current) || current < 0) current = 0
  var step = Number(delta)
  if (!isFinite(step)) step = 0
  return ((current + step) % size + size) % size
}

function shortenedTitle(value, limit) {
  var text = String(value || "").replace(/\s+/g, " ").trim()
  var maximum = Math.max(1, Number(limit) || 80)
  return text.length <= maximum ? text : text.slice(0, maximum - 1) + "…"
}
