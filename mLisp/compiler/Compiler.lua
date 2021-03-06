local _M = {}

local function ensureBuffSize(self, size)
	local oldSize = self.buffSize

	if oldSize >= size then
		return
	end

	local buff = self.buff
	for i = oldSize + 1, size do--fill in blank slots
		buff[i] = {}
	end

	local lastLine = self.buff[size]

	self.buffSize = size
end

local compile

local function emit(self, line, data, ...)
	if data == nil then
		data = line
		line = self.buffSize
	end
	ensureBuffSize(self, line)
	local targetLine = self.buff[line]
	table.insert(targetLine, data)
	for _, v in ipairs(arg) do
		table.insert(targetLine, v)
	end
	return true
end

local function compileFunctionCall(self, resultUsage, list)
	local firstChild = list[1]
	local childType, childData, childLine = unpack(firstChild)

	if resultUsage == "return" then
		emit(self, childLine, "return ")
	end
	compile(self, "asParam", firstChild)--the function
	emit(self, "(")--begin list of arguments
	for i = 2, #list do--generate expression for arguments
		compile(self, "asParam", list[i])
		if i ~= #list then
			emit(self, ", ")--separate arguments
		end
	end
	--end list of arguments
	if resultUsage == "asParam" then
		return emit(self, ")")
	else
		return emit(self, ");")--return or ignore
	end
end

local function _compile(self, resultUsage, exp)
	local type, data, line, pos, depth = unpack(exp)
	--update indentLevel
	self.indentLevel[line] = self.indentLevel[line] or depth - 1

	if type == "List" then
		local firstChild = data[1]
		if firstChild then
			local childType, childData, childLine = unpack(firstChild)
			if childType == "Symbol" then--a special form or a function call
				local sf = self.lang.specialForms[childData]
				if sf then--a special form
					local needLambda = self.lang.wrapWithLambda[childData] --check if the special form need to be surrounded with a lambda
					if not needLambda or resultUsage ~= "asParam" then
						return sf(self, resultUsage, data)
					else--wrap around a lambda
						emit(self, childLine, "(function() ")
						sf(self, "return", data)--tell it to return the value
						return emit(self, " end)() ")
					end
				else--probably a function
					return compileFunctionCall(self, resultUsage, data)
				end
			elseif childType == "List" then--a compound call
				return compileFunctionCall(self, resultUsage, data)
			end
		else
			error("Empty list at "..line)
		end
	elseif type == "Symbol" or type == "Number" then--TODO:separate
		data = self.lang.aliases[data] or data
		if resultUsage == "return" then
			return emit(self, line, "return ", data, ';')
		elseif resultUsage == "asParam" then
			return emit(self, line, data)
		else
			print("Warning: unused symbol "..data.." line "..line.." pos "..pos)
			return true
		end
	elseif type == "String" then
		if resultUsage == "return" then
			emit(self, line, 'return "', data,'";')
		elseif resultUsage == "asParam" then
			emit(self, line, '"', data, '"')
		else
			print("Warning: unused string "..data.." line "..line.." pos "..pos)
			return true
		end
	else
		error("Unknown type at "..line)
	end
end

compile = function(self, ...)
	return _compile(self, ...)
end

local function generateCode(self)
	local code = {}
	for line = 1, self.buffSize do
		local indentLevel = self.indentLevel[line] or 0
		--indent the line
		for i = 1, indentLevel do
			table.insert(code, "   ")
		end
		--push line
		local lineContent = self.buff[line]
		for i, str in ipairs(lineContent) do
			table.insert(code, str)
		end
		table.insert(code, "\n")--line break
	end
	return table.concat(code)
end

local function generateUniqueName(self)
	local counter = self.counter
	local name = "__unique_"..counter
	self.counter = counter + 1
	return name
end

--export functions
local Compiler = {
	compile = compile,
	emit = emit,
	generateCode = generateCode,
	generateUniqueName = generateUniqueName
}

function _M.new(languageDef)
	return setmetatable(
		{
			lang = languageDef,
			buffSize = 0,
			buff = {},
			counter = 0,
			indentLevel = {}
		},
		{__index = Compiler}
	)
end

return _M
