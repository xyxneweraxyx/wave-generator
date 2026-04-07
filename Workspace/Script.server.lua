--/ SERVICES & REQUIRES

local ss = game:GetService("ServerStorage")

--/ TYPES

-- Every relevant measurement is in studs
type waveParams = {
	
	ocean: {MeshPart}, -- Usually a :GetChildren() of something that contains all the oceans you need. (cuz roblox won't let you add bones ingame)
	-- Please note that the only requirement is for every meshpart to have bones inside. Those are used to move the wave
	axis: "X" | "Z", -- Axis that the wave will follow
	direction: "forward" | "backward", -- Direction that the wave will follow on the axis

	speed: number, -- Speed in studs/sec
	height: number, -- Height in studs
	amplitude: number, -- Total amplitude of the wave in studs
	steepness: number, -- steepness of the wave's edges

	noiseMaxAdd: number, -- Multiplier for the noise. The higher it is, the more the noise will be visible on the wave.
	noiseRoughnessX: number, -- Stretches the noise in the X axis
	noiseRoughnessY: number, -- Stretches the noise in the Y axis
	noiseRoughnessZ: number, -- Stretches the noise in the Z axis

	noiseApplyMode: "allWave" | "towardsCenter",
	easingFactor: number, -- An exponent applied to the noise in towardsCenter mode. Determines how sharply the noise reduces as it approaches center
	--[[allWave multiplies by noiseMaxAdd on entire wave equally.
	    towardsCenter diminishes noiseMaxAdd the further from the wave's center point]]
	
	isFoam: boolean, -- Are there foam particles on top of the wave
	foamEmitter: ParticleEmitter?, -- You can use any particle emitter you want if isFoam is enabled.
	foamThicknessFactor: number?, -- Changes how many emitters will be present on the wave's height. Smaller number = less emitters.
	
	isTextureMoving: boolean, -- Is the texture of the ocean moving
	textureMoveSpeed: number, -- If texture is moving, speed at which it moves

	fps: number, -- Amount of times the wave will attempt to update in one second. Drastically influences performance during runtime and creation
	framesLoadedPerFrame: number, -- Amount of frames that will be created each frame. Drastically influences performance during creation
	
}

--[[
	Note to help users with noise :
	Stretching the noise in the wave's axis influence how quick it changes form
	Stretching the noise in the wave's opposite axis influences how sharp/rough it is
	Stretching the noise in the Y axis adds a little big of randomness and roughness
	Furthermore, please note that all noise factors should depend on the wave's height+amplitude.
]]

type completedWave = {
	
	bulkMoves: {CFrame},
	bulkBones: {{Bone}},
	
	params: waveParams,
	
	foam: {
		isFoam: boolean?,
		foamEmitterTable: {ParticleEmitter}?,
		foamAxisTable: {number}?,
		foamMoveTable: {{CFrame}}?,
	},
	
}

type boneTable = {
	{{
		bone: Bone,
		pos: Vector3,
		worldPos: Vector3
	}}
}

--/ FUNCTIONS

-- d being the amount of digits you round up to
local function round(x: number, d: number)
	return tonumber(string.sub(tostring(x), 1, d+2))
end

function calculateGridSize(meshparts)

	-- Initialize min and max corners with extreme values
	local minCorner = Vector3.new(math.huge, math.huge, math.huge)
	local maxCorner = Vector3.new(-math.huge, -math.huge, -math.huge)

	-- Iterate through all meshparts
	for _, part in meshparts do
		-- Get the part's CFrame and Size
		local cf = part.CFrame
		local size = part.Size

		-- Calculate all 8 corners of the meshpart in world space
		local corners = {
			cf * Vector3.new(-size.X/2, -size.Y/2, -size.Z/2),
			cf * Vector3.new(-size.X/2, -size.Y/2, size.Z/2),
			cf * Vector3.new(-size.X/2, size.Y/2, -size.Z/2),
			cf * Vector3.new(-size.X/2, size.Y/2, size.Z/2),
			cf * Vector3.new(size.X/2, -size.Y/2, -size.Z/2),
			cf * Vector3.new(size.X/2, -size.Y/2, size.Z/2),
			cf * Vector3.new(size.X/2, size.Y/2, -size.Z/2),
			cf * Vector3.new(size.X/2, size.Y/2, size.Z/2)
		}

		-- Find the minimum and maximum coordinates
		for _, corner in ipairs(corners) do
			minCorner = Vector3.new(
				math.min(minCorner.X, corner.X),
				math.min(minCorner.Y, corner.Y),
				math.min(minCorner.Z, corner.Z)
			)

			maxCorner = Vector3.new(
				math.max(maxCorner.X, corner.X),
				math.max(maxCorner.Y, corner.Y),
				math.max(maxCorner.Z, corner.Z)
			)
		end
	end

	-- Calculate the total grid size
	local totalSize = maxCorner - minCorner

	-- Calculate the center point in world space
	local centerPoint = minCorner + (totalSize / 2)

	return {totalSize = totalSize, centerPoint = centerPoint}
end

local function createBoneSortTables(ocean: {MeshPart}, axis: "X" | "Z"): {boneTable: boneTable, sortTable: {number}}

	if not axis then print("Forgot axis!") return nil end
	if typeof(ocean) ~= "table" then print("Ocean has to be a table of meshparts! Use GetChildren!") return nil end

	local otherAxis = axis == "Z" and "X" or "Z"
	local boneTable = {}

	for _,meshpart in ocean do
		for _,bone in meshpart:GetChildren() do
			if not bone:IsA("Bone") then continue end
			local bonePos = bone.WorldPosition[axis]
			if not boneTable[bonePos] then boneTable[bonePos] = {} end
			table.insert(boneTable[bonePos], {bone = bone, pos = bone.Position, worldPos = bone.WorldPosition})
		end
	end

	local sortTable = {}
	for key,_ in boneTable do
		table.insert(sortTable, key)
	end
	table.sort(sortTable)

	return {boneTable = boneTable, sortTable = sortTable}

end

local function createWave(params: waveParams)
	
	local clock = os.clock()

	-- Get the parameters
	local ocean = params.ocean
	local axis = params.axis
	local direction = params.direction

	local speed = params.speed
	local height = params.height
	local amplitude = params.amplitude
	local steepness = params.steepness

	local noiseMaxAdd = params.noiseMaxAdd
	local noiseRoughnessX = params.noiseRoughnessX
	local noiseRoughnessY = params.noiseRoughnessY
	local noiseRoughnessZ = params.noiseRoughnessZ
	
	local isFoam      = params.isFoam
	local foamEmitter = params.foamEmitter
	local foamThicknessFactor = params.foamThicknessFactor

	local noiseApplyMode = params.noiseApplyMode
	local easingFactor   = params.easingFactor
	
	local isTextureMoving = params.isTextureMoving
	local textureMoveSpeed = params.textureMoveSpeed

	local fps = params.fps
	local framesLoadedPerSecond = params.framesLoadedPerFrame
	
	if steepness == 0 then steepness = 0.01 end -- Ensure that steepness isn't 0, which makes everything blank

	-- Initialize the bone tables
	local boneSort = createBoneSortTables(ocean, axis)
	if not boneSort then print("There was a problem creating the bones table!") return nil end
	local boneTable = boneSort.boneTable
	local sortTable = boneSort.sortTable
	
	-- Initialize the foam tables if needed
	local foamEmitterTable = {}
	local foamAxisTable = {}
	local foamMoveTable = {}
	local foamProximityBones = {}
	
	local gridSize = calculateGridSize(ocean)
	local totalSize = gridSize.totalSize
	local centerPoint = gridSize.centerPoint
	local otherAxis = axis == "Z" and "X" or "Z"
	
	-- Create some foam to be used later (with it's position on the wave as the key)
	if isFoam then
		
		if not foamEmitter then print("There's no foam emitter provided!") return nil end
		
		-- Create some emitters in a folder and give them the correct coordinate to align with the wave
		local emitterSize = math.huge
		for _,keypoint in foamEmitter.Size.Keypoints do
			if keypoint.Value < emitterSize then emitterSize = keypoint.Value end
		end
		local dividedBySize = totalSize[otherAxis]/emitterSize
		
		local emittersFolder = Instance.new("Folder")
		local part = Instance.new("Part")
		part.Size = Vector3.one
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Transparency = 0.7
		part.Parent = emittersFolder
		
		for i = -dividedBySize/2,dividedBySize/2,1/foamThicknessFactor do -- a remplacer par une valeur configurable pour augmenter/diminuer le nb de particleemitters
			
			local newPart = part:Clone()
			local pos = centerPoint[otherAxis] + i*emitterSize
			
			local newParticleEmitter = foamEmitter:Clone()
			if otherAxis == "X" then
				newPart.Position = Vector3.new(pos, 0, 0)
			else
				newPart.Position = Vector3.new(0, 0, pos)
			end
			newParticleEmitter.Parent = newPart
			newPart.Parent = emittersFolder
			
			table.insert(foamEmitterTable, newPart)
			table.insert(foamAxisTable, pos)
			
		end
		
		local boneTable = createBoneSortTables(ocean, otherAxis)
		local bonesUsed = boneTable.boneTable[centerPoint[otherAxis]+totalSize[otherAxis]/2]
		
		-- Make a table with the closest bones to each emitter (to use for height calculations later)
		for i,emitter in foamEmitterTable do
			
			local closestBone, secondClosestBone
			local closestBoneDist, secondClosestBoneDist = math.huge, math.huge
			
			for _,boneData in bonesUsed do
				local dist = math.abs(boneData.worldPos[axis] - foamAxisTable[i])
				if dist < closestBoneDist then
					secondClosestBone = closestBone
					secondClosestBoneDist = closestBoneDist
					closestBone = boneData.bone
					closestBoneDist = dist
					continue
				end
				if dist < secondClosestBoneDist then
					secondClosestBone = boneData.bone
					secondClosestBoneDist = dist
				end
			end
			
			local result = {closestBone = closestBone, secondClosestBone = secondClosestBone}
			foamProximityBones[emitter] = result
			
		end
		
		emittersFolder.Parent = workspace
		
	end

	-- Create the tables for bulk lerping
	local bulkMoves  = {}
	local bulkBones  = {}
	local waveCenter = direction == "forward" and sortTable[1] - amplitude/2 or sortTable[#sortTable] + amplitude/2
	-- Moving by amplitude/2 to show the wave coming on the ocean
	local duration   = math.abs((sortTable[#sortTable] - sortTable[1] + amplitude) / speed)
	
	-- Initializing some constants to ease off maths
	local outsideThreshold = (amplitude*fps)/(2*speed)
	local divisor = math.exp(-1*steepness*math.cos(math.pi))-1
	local amplFactor = math.pi/amplitude
	-- Outside of this threshold the wave's top is outside the noise is diminished not to look too rough
	
	for i = 1,fps*duration+1 do

		if i % framesLoadedPerSecond == 0 then task.wait() end

		if direction == "forward" then waveCenter += speed/fps else waveCenter -= speed/fps end
		bulkMoves[i] = {}
		bulkBones[i] = {}

		-- Fetch which bones we'll calculate this frame
		local concernedBones = {}
		for pos,boneList in boneTable do
			if math.abs(pos-waveCenter) <= (amplitude/2)*1.1 then -- Little addition parts going "below" and resetting back to Y=0
				for _,boneData in boneList do table.insert(concernedBones, boneData) end
			end
		end

		local noiseMulti = math.min(i, fps*duration+1-i) > outsideThreshold and noiseMaxAdd or noiseMaxAdd*(math.min(i, fps*duration+1-i)/outsideThreshold)
		
		-- Calculate the bone's height in the frame
		for _,boneData in concernedBones do

			local bonePos      = boneData.pos
			local worldBonePos = boneData.worldPos
			local bone         = boneData.bone
			
			local relativeToCenter = worldBonePos[axis] - waveCenter
			local insideExp    = steepness*math.cos((relativeToCenter)*amplFactor)
			local pointHeight  = (height/divisor)*(math.exp(insideExp)-1)

			local noise        = math.noise(worldBonePos.X*noiseRoughnessX/100, pointHeight*noiseRoughnessY/100, worldBonePos.Z*noiseRoughnessZ/100)
			local centerFactor = math.pow(math.clamp(2*((50-math.abs(relativeToCenter))/amplitude), 0, noiseMaxAdd), easingFactor)
			if noiseApplyMode == "towardsCenter" then
				pointHeight += noise*noiseMulti*centerFactor
			else
				pointHeight += noise*noiseMulti
			end

			local realHeight  = pointHeight > 0 and pointHeight or 0
			local cFrame      = CFrame.new(bonePos.X, realHeight, bonePos.Z)
			table.insert(bulkMoves[i], cFrame)
			table.insert(bulkBones[i], bone)

		end
		
		if not isFoam then continue end
		
		foamMoveTable[i] = {}
		
		for j,foam in foamEmitterTable do
			
			local foamX, foamZ
			local pos = foamAxisTable[j]
			
			local closestBone = foamProximityBones[foam].closestBone
			local secondClosestBone = foamProximityBones[foam].secondClosestBone
			
			if axis == "X" then
				foamX = waveCenter-10 -- keep it ahead a bit
				foamZ = pos
			else
				foamZ = waveCenter-10
				foamX = pos
			end
			
			table.insert(foamMoveTable[i], CFrame.new(Vector3.new(foamX, height, foamZ)))
			
		end

	end
	print((os.clock()-clock)*1000)
	
	local foam = {isFoam = isFoam, foamEmitterTable = foamEmitterTable, foamAxisTable = foamAxisTable, foamMoveTable = foamMoveTable}
	local finalTable: completedWave = {bulkMoves = bulkMoves, bulkBones = bulkBones, params = params, foam = foam}
	return finalTable

end

local function playWave(wave: completedWave)
	
	local wavePlaying = true

	local bulkMoves = wave.bulkMoves
	local bulkBones = wave.bulkBones
	
	local params = wave.params
	
	local foam = wave.foam
	local isFoam = foam.isFoam
	local emitterTable = foam.foamEmitterTable or nil
	local moveTable = foam.foamMoveTable or nil
	
	local direction = params.direction
	local fps       = params.fps
	
	local isTextureMoving = params.isTextureMoving
	local textureMoveSpeed = params.textureMoveSpeed
	
	local bulkAmount = #bulkMoves
	
	if direction == "forward" then textureMoveSpeed *= -1 end
	
	task.spawn(function()
		while wavePlaying do
			task.wait()
			workspace.ocean.Ocean.Texture.OffsetStudsV += textureMoveSpeed
		end
	end)

	for i = 1,bulkAmount do
		task.wait(1/fps)
		for j,bone: Bone in bulkBones[i] do
			bone.CFrame = bulkMoves[i][j]
		end
		if isFoam then workspace:BulkMoveTo(emitterTable, moveTable[i], Enum.BulkMoveMode.FireCFrameChanged) end
	end
	
	wavePlaying = false

end

--/ RUNTIME

task.wait(2)

local params: waveParams = {
	ocean     = workspace.ocean:GetChildren(),
	axis      = "Z",
	direction = "backward",

	speed     = 30,
	height    = 50,
	amplitude = 75,
	steepness = 2,

	noiseMaxAdd = 15,
	noiseRoughnessX = 0.5,
	noiseRoughnessY = 3,
	noiseRoughnessZ = 3,
	
	isFoam      = false,
	foamEmitter = ss.ParticleEmitter,
	foamThicknessFactor = 0.5,

	noiseApplyMode = "allWave",
	easingFactor   = 1,
	
	isTextureMoving  = true,
	textureMoveSpeed = .25,

	fps = 60,
	framesLoadedPerFrame = 50,
}
local wave = createWave(params)
if wave then
	task.spawn(function() playWave(wave) end)
else
	print("Problem generating the wave!")
end