function server.hasGroup(inv, group)
	if type(group) == 'table' then
		for name, rank in pairs(group) do
			local groupRank = inv.player.groups[name]
			if groupRank and groupRank >= (rank or 0) then
				return name, groupRank
			end
		end
	else
		local groupRank = inv.player.groups[group]
		if groupRank then
			return group, groupRank
		end
	end
end

function server.setPlayerData(player)
	if not player.groups then
		shared.warning(("server.setPlayerData did not receive any groups for '%s'"):format(player?.name or GetPlayerName(player)))
	end

	return {
		source = player.source,
		name = player.name,
		groups = player.groups or {},
		sex = player.sex,
		dateofbirth = player.dateofbirth,
	}
end

if shared.framework == 'esx' then
	local ESX

	SetTimeout(4000, function()
		ESX = exports.es_extended:getSharedObject()

		if ESX.CreatePickup then
			error('ox_inventory requires a ESX Legacy v1.6.0 or above, refer to the documentation.')
		end

		server.UseItem = ESX.UseItem
		server.GetPlayerFromId = ESX.GetPlayerFromId
		server.UsableItemsCallbacks = ESX.GetUsableItems()

		for _, player in pairs(ESX.Players) do
			exports.ox_inventory:setPlayerInventory(player, player?.inventory)
		end
	end)

	-- Accounts that need to be synced with physical items
	server.accounts = {
		money = 0,
		black_money = 0,
	}

	function server.setPlayerData(player)
		local groups = {
			[player.job.name] = player.job.grade
		}

		return {
			source = player.source,
			name = player.name,
			groups = groups,
			sex = player.sex or player.variables.sex,
			dateofbirth = player.dateofbirth or player.variables.dateofbirth,
		}
	end

	function server.syncInventory(inv)
		local money = table.clone(server.accounts)

		for _, v in pairs(inv.items) do
			if money[v.name] then
				money[v.name] += v.count
			end
		end

		local player = server.GetPlayerFromId(inv.id)
		player.syncInventory(inv.weight, inv.maxWeight, inv.items, money)
	end

elseif shared.framework == 'qb' then
	local QBCore = exports['qb-core']:GetCoreObject()

	SetTimeout(4000, function()
		local qbPlayers = QBCore.Functions.GetQBPlayers()
		for _, Player in pairs(qbPlayers) do
			if Player then
				QBCore.Functions.AddPlayerField(Player.PlayerData.source, 'syncInventory', function(_, _, items, money)
					Player.Functions.SetPlayerData('items', items)
					Player.Functions.SetPlayerData('inventory', items)

					if money?.cash then Player.Functions.SetMoney('cash', money.cash, "Sync money with inventory") end
				end)

				Player.Functions.SetPlayerData('inventory', Player.PlayerData.items)

				Player.Functions.inventory = Player.PlayerData.items

				Player.PlayerData.identifier = Player.PlayerData.citizenid

				exports.ox_inventory:setPlayerInventory(Player.PlayerData)

				QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "AddItem", function(item, amount, slot, info)
					server.inventory.AddItem(Player.PlayerData.source, item, amount, info, slot)
				end)

				QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "RemoveItem", function(item, amount, slot)
					server.inventory.RemoveItem(Player.PlayerData.source, item, amount, nil, slot)
				end)

				QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemBySlot", function(slot)
					return server.inventory.GetSlot(Player.PlayerData.source, slot)
				end)

				QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemByName", function(item)
					return server.inventory.GetItem(Player.PlayerData.source, item, nil, false)
				end)

				QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemsByName", function(item)
					return server.inventory.Search(Player.PlayerData.source, 'slots', item)
				end)

				QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "ClearInventory", function(filterItems)
					server.inventory.Clear(Player.PlayerData.source, filterItems)
				end)

				QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "SetInventory", function()
					-- ox_inventory's item structure is not compatible with qb-inventory's one so we don't support it
					shared.info('Player.Functions.SetInventory is unsupported for ox_inventory, please use exports.ox_inventory:setPlayerInventory instead.')
				end)
			end
		end
	end)

	local itemCallbacks = {}

	QBCore.Functions.SetMethod('CreateUseableItem', function(item, cb)
		itemCallbacks[item] = cb
	end)

	server.UseItem = function(source, itemName, ...)
		local callback = itemCallbacks[itemName].callback or itemCallbacks[itemName].cb or type(itemCallbacks[itemName]) == "function" and itemCallbacks[itemName]

		if not callback then return end

		callback(source, itemName, ...)
	end

	AddEventHandler('QBCore:Player:SetPlayerData', function(val)
		local cash = server.inventory.GetItem(val.source, 'money', nil, false)

		if not cash or cash.count == 0 then
			if val.money.cash > 0 then server.inventory.AddItem(val.source, 'money', val.money.cash) end
			return
		end

		if val.money.cash > 0 then
			server.inventory.SetItem(val.source, 'money', val.money.cash)
		else
			server.inventory.RemoveItem(val.source, 'money', cash.count)
		end
	end)

	AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
		QBCore.Functions.AddPlayerField(Player.PlayerData.source, 'syncInventory', function(_, _, items, money)
			Player.Functions.SetPlayerData('items', items)
			Player.Functions.SetPlayerData('inventory', items)

			if money?.cash then Player.Functions.SetMoney('cash', money.cash, "Sync money with inventory") end
		end)

		Player.Functions.SetPlayerData('inventory', Player.PlayerData.items)

		Player.Functions.inventory = Player.PlayerData.items

		Player.PlayerData.identifier = Player.PlayerData.citizenid

		exports.ox_inventory:setPlayerInventory(Player.PlayerData)

		QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "AddItem", function(item, amount, slot, info)
			server.inventory.AddItem(Player.PlayerData.source, item, amount, info, slot)
		end)

		QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "RemoveItem", function(item, amount, slot)
			server.inventory.RemoveItem(Player.PlayerData.source, item, amount, nil, slot)
		end)

		QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemBySlot", function(slot)
			return server.inventory.GetSlot(Player.PlayerData.source, slot)
		end)

		QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemByName", function(item)
			return server.inventory.GetItem(Player.PlayerData.source, item, nil, false)
		end)

		QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemsByName", function(item)
			return server.inventory.Search(Player.PlayerData.source, 'slots', item)
		end)

		QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "ClearInventory", function(filterItems)
			server.inventory.Clear(Player.PlayerData.source, filterItems)
		end)

		QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "SetInventory", function()
			-- ox_inventory's item structure is not compatible with qb-inventory's one so we don't support it
			shared.info('Player.Functions.SetInventory is unsupported for ox_inventory, please use exports.ox_inventory:setPlayerInventory instead.')
		end)
	end)

	local usableItems = {}

	for k, v in pairs(QBCore.Shared.Items) do
		if v.useable then usableItems[k] = true end
	end

	server.UsableItemsCallbacks = usableItems
	server.GetPlayerFromId = QBCore.Functions.GetPlayer

	-- Accounts that need to be synced with physical items
	server.accounts = {
		cash = 0
	}

	function server.setPlayerData(player)
		local groups = {
			[player.job.name] = player.job.grade.level,
			[player.gang.name] = player.gang.grade.level
		}

		return {
			source = player.source,
			name = player.name,
			groups = groups,
			sex = player.charinfo.gender,
			dateofbirth = player.charinfo.birthdate,
		}
	end

	function server.syncInventory(inv)
		local money = table.clone(server.accounts)

		for _, v in pairs(inv.items) do
			if money[v.name] then
				money[v.name] += v.count
			end
		end

		local player = server.GetPlayerFromId(inv.id)
		player.syncInventory(inv.weight, inv.maxWeight, inv.items, money)
	end
end
