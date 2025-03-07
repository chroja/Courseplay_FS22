--- High level control of the Course object in the vehicle.
--- TODO: improve relations to the courseManager

---@class CpCourseManager
CpCourseManager = {}

CpCourseManager.MOD_NAME = g_currentModName

CpCourseManager.KEY = "."..CpCourseManager.MOD_NAME..".cpCourseManager."
CpCourseManager.xmlKey = "Course"
CpCourseManager.rootKey = "AssignedCourses"
CpCourseManager.rootKeyFileManager = "Courses"
CpCourseManager.xmlKeyFileManager = "Courses.Course"

CpCourseManager.i18n = {
	["noCurrentCourse"] = "CP_courseManager_no_current_course",
	["temporaryCourse"] = "CP_courseManager_temporary_course",
}
CpCourseManager.vehicles = {}

--- generic xml course schema for saving/loading.
function CpCourseManager.registerXmlSchemaValues(schema,baseKey)
	baseKey = baseKey or ""
	schema:register(XMLValueType.STRING, baseKey .. "#name", "Course name")
	schema:register(XMLValueType.FLOAT, baseKey  .. "#workWidth", "Course work width")
	schema:register(XMLValueType.INT, baseKey .. "#numHeadlands", "Course number of headlands")
	schema:register(XMLValueType.INT, baseKey .. "#multiTools", "Course multi tools")
    schema:register(XMLValueType.BOOL, baseKey .. "#isSavedAsFile", "Course is saved as file or temporary ?",false)
	schema:register(XMLValueType.STRING, baseKey .. ".waypoints", "Course serialized waypoints")
end

function CpCourseManager.initSpecialization()
    CpCourseManager.xmlSchema = XMLSchema.new("Course")
	local schema = CpCourseManager.xmlSchema
	CpCourseManager.registerXmlSchemaValues(schema,CpCourseManager.xmlKeyFileManager .."(?)")

    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpCourseManager.KEY .. CpCourseManager.rootKey
---    schema:register(XMLValueType.BOOL, key .. "#hasTemporaryCourses","Are the courses a temporary and not saved?",false)
	CpCourseManager.registerXmlSchemaValues(schema,key.."(?)")
end

function CpCourseManager.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(AIFieldWorker, specializations) 
end

function CpCourseManager.registerEventListeners(vehicleType)	
--	SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", CpCourseManager)
	SpecializationUtil.registerEventListener(vehicleType, "onLoad", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "cpOnCourseChange", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onPreDelete", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "cpUpdateWaypointVisibility", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", CpCourseManager)
end

function CpCourseManager.registerEvents(vehicleType)
    SpecializationUtil.registerEvent(vehicleType, 'cpUpdateWaypointVisibility', CpCourseManager.cpUpdateWaypointVisibility)
    SpecializationUtil.registerEvent(vehicleType, 'cpOnCourseChange', CpCourseManager.cpOnCourseChange)
end

function CpCourseManager.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, 'setFieldWorkCourse', CpCourseManager.setFieldWorkCourse)
    SpecializationUtil.registerFunction(vehicleType, 'getFieldWorkCourse', CpCourseManager.getFieldWorkCourse)
    SpecializationUtil.registerFunction(vehicleType, 'addCpCourse', CpCourseManager.addCourse)
    SpecializationUtil.registerFunction(vehicleType, 'getCpCourses', CpCourseManager.getCourses)
    SpecializationUtil.registerFunction(vehicleType, 'hasCpCourse', CpCourseManager.hasCourse)
    
    SpecializationUtil.registerFunction(vehicleType, 'appendLoadedCpCourse', CpCourseManager.appendLoadedCourse)
    SpecializationUtil.registerFunction(vehicleType, 'saveCpCourses', CpCourseManager.saveCourses)
    SpecializationUtil.registerFunction(vehicleType, 'resetCpCourses', CpCourseManager.resetCourses)
    SpecializationUtil.registerFunction(vehicleType, 'getCurrentCpCourseName', CpCourseManager.getCurrentCourseName)
    
    SpecializationUtil.registerFunction(vehicleType, 'drawCpCoursePlot', CpCourseManager.drawCoursePlot)
    
    SpecializationUtil.registerFunction(vehicleType, 'loadAssignedCpCourses', CpCourseManager.loadAssignedCourses)
    SpecializationUtil.registerFunction(vehicleType, 'saveAssignedCpCourses', CpCourseManager.saveAssignedCourses)

    SpecializationUtil.registerFunction(vehicleType, 'getCpLegacyWaypoints', CpCourseManager.getLegacyWaypoints)

    SpecializationUtil.registerFunction(vehicleType, 'cpStartCourseRecorder', CpCourseManager.cpStartCourseRecorder)
    SpecializationUtil.registerFunction(vehicleType, 'cpStopCourseRecorder', CpCourseManager.cpStopCourseRecorder)
end

function CpCourseManager:onLoad(savegame)
	--- Register the spec: spec_cpCourseManager 
    local specName = CpCourseManager.MOD_NAME .. ".cpCourseManager"
    self.spec_cpCourseManager  = self["spec_" .. specName]
    local spec = self.spec_cpCourseManager 
    spec.coursePlot = CoursePlot(g_currentMission.inGameMenu.ingameMap)
    spec.courseRecorder = CourseRecorder()

    spec.courses = {}
    
 --   TODO: make this an instance similar to course plot
 --   self.courseDisplay = CourseDisplay() 
    CpCourseManager.vehicles[self.id] = self

    spec.legacyWaypoints = {}
end

function CpCourseManager:onPostLoad(savegame)
    if savegame == nil or savegame.resetVehicles then return end
    CpCourseManager.loadAssignedCourses(self,savegame.xmlFile,savegame.key..CpCourseManager.KEY..CpCourseManager.rootKey)
end

function CpCourseManager:loadAssignedCourses(xmlFile,baseKey)
    local spec = self.spec_cpCourseManager 
    local courses = {}
    xmlFile:iterate(baseKey,function (i,key)
        local course = Course.createFromXml(self,xmlFile,key)
        course:setVehicle(self)
        table.insert(courses,course)
    end)    
    if courses ~= nil and next(courses) then
        spec.courses = courses
        SpecializationUtil.raiseEvent(self,"cpOnCourseChange",courses[1])
    end
end

function CpCourseManager:saveToXMLFile(xmlFile, baseKey, usedModNames)
    CpCourseManager.saveAssignedCourses(self,xmlFile, baseKey.."."..CpCourseManager.rootKey)
end

function CpCourseManager:saveAssignedCourses(xmlFile, baseKey,name)
    local spec = self.spec_cpCourseManager 
    local courses = spec.courses
    if courses ~=nil and next(courses) then
        for i=1,#courses do 
            local key = string.format("%s(%d)",baseKey,i-1)
            local course = courses[i]
            if name then 
                course:setName(name)
            end
            course:saveToXml(xmlFile, key)
        end
    end
end

---@param course  Course
function CpCourseManager:setFieldWorkCourse(course)
    CpCourseManager.resetCourses(self)
    CpCourseManager.addCourse(self,course)   
end

function CpCourseManager:addCourse(course)
    local spec = self.spec_cpCourseManager 
    course:setVehicle(self)
    table.insert(spec.courses,course)
    SpecializationUtil.raiseEvent(self,"cpOnCourseChange",course)
end

function CpCourseManager:resetCourses()
    local spec = self.spec_cpCourseManager 
    spec.courses = {}
    SpecializationUtil.raiseEvent(self,"cpOnCourseChange")
end

---@return Course
function CpCourseManager:getFieldWorkCourse()
    local spec = self.spec_cpCourseManager 
    --- TODO: For now only returns the first course.
    return spec.courses[1]
end

function CpCourseManager:getCourses()
    local spec = self.spec_cpCourseManager 
    return spec.courses
end

function CpCourseManager:hasCourse()
    local spec = self.spec_cpCourseManager 
    return next(spec.courses) ~= nil
end


function CpCourseManager:cpUpdateWaypointVisibility()
    g_courseDisplay:updateWaypointSigns(self)
end

function CpCourseManager:onEnterVehicle(isControlling)
    if isControlling then
        g_courseDisplay:setSignsVisibility(self);
    end
end

function CpCourseManager:onLeaveVehicle(wasEntered)
    if wasEntered then
        g_courseDisplay:setSignsVisibility(self, true);
    end
end

function CpCourseManager:cpOnCourseChange(newCourse)
    local spec = self.spec_cpCourseManager
    if newCourse then 
        -- we have course, show the course plot on the AI helper screen
        spec.coursePlot:setWaypoints(newCourse.waypoints)
        spec.coursePlot:setVisible(true)
    else 
        spec.coursePlot:setVisible(false)
    end
    if g_client then
        CpCourseManager.updateLegacyWaypoints(self)
        g_courseDisplay:updateWaypointSigns(self)
        g_courseDisplay:setSignsVisibility(self, not self:getIsControlled())
	end

end

function CpCourseManager:drawCoursePlot(map)
    if CpCourseManager.hasCourse(self) then
        local spec = self.spec_cpCourseManager
        spec.coursePlot:draw(map)
    end
end

function CpCourseManager:onDraw()
--    self.courseDisplay:draw()
end

function CpCourseManager:onReadStream(streamId)

end

function CpCourseManager:onWriteStream(streamId)
	
end

function CpCourseManager:onPreDelete()
    CpCourseManager.vehicles[self.id] = nil
    CpCourseManager.resetCourses(self)
end

------------------------------------------------------------------------
-- Interaction between the course manager frame and the vehicle courses.
------------------------------------------------------------------------

function CpCourseManager:getCurrentCourseName()
    if CpCourseManager.hasCourse(self) then 
        local courses = CpCourseManager.getCourses(self)
        local name =  CpCourseManager.getCourseName(courses[1])
        for i = 2,#courses do 
            name = string.format("%s + %s",name,CpCourseManager.getCourseName(courses[i]))
        end  
      --  name = string.format("%s (%d)",name,#courses)
        return name
    end
    return g_i18n:getText(CpCourseManager.i18n.noCurrentCourse)
end

function CpCourseManager.getCourseName(course)
	local name = course:getName()
   -- local isSavedAsFile = course:isSavedAsFile()
  --  if not isSavedAsFile or name == "" then 
    if name == "" then
       return g_i18n:getText(CpCourseManager.i18n.temporaryCourse)
    end
    return name
end

function CpCourseManager:appendLoadedCourse(file)
    --- For now clear the previous courses.
    CpCourseManager.resetCourses(self)
    file:load(CpCourseManager.xmlSchema,CpCourseManager.xmlKeyFileManager,
    CpCourseManager.loadAssignedCourses,self)
end

function CpCourseManager:saveCourses(file,text)
    file:save(CpCourseManager.rootKeyFileManager,CpCourseManager.xmlSchema,
    CpCourseManager.xmlKeyFileManager,CpCourseManager.saveAssignedCourses,self,text)
end

function CpCourseManager.getValidVehicles()
    return CpCourseManager.vehicles
end

function CpCourseManager:appendCourse(course)

end

function CpCourseManager:getFieldworkCourseLegacy(vehicle)
	for _, course in ipairs(CpCourseManager.getCourses(self)) do
		if course:isFieldworkCourse() then
			CpUtil.debugVehicle(CpDebug.DBG_COURSES,vehicle, 'getting fieldwork course %s', course:getName())
			return course
		end
	end
end

--- For backwards compatibility, create all waypoints of all loaded courses for this vehicle, as it
--- used to be stored in the terrible global Waypoints variable
--- Update all the legacy (as usual global) data structures related to a vehicle's loaded course
-- TODO: once someone has the time and motivation, refactor those legacy structures
function CpCourseManager:updateLegacyWaypoints()
    local spec = self.spec_cpCourseManager 
	spec.legacyWaypoints = {}
	local n = 1
	for _, course in ipairs(CpCourseManager.getCourses(self)) do
		for i = 1, course:getNumberOfWaypoints() do
			table.insert(spec.legacyWaypoints, Waypoint(course:getWaypoint(i), n))
			n = n +1
		end
	end
end

function CpCourseManager:getLegacyWaypoints()
    local spec = self.spec_cpCourseManager 
	return spec and spec.legacyWaypoints
end

------------------------------------------------------------------------------------------------------------------------
--- Recording
------------------------------------------------------------------------------------------------------------------------
function CpCourseManager:onUpdate()
    local spec = self.spec_cpCourseManager
    spec.courseRecorder:update()
end

function CpCourseManager:cpStartCourseRecorder()
    local spec = self.spec_cpCourseManager
    spec.courseRecorder:start(self)
end

function CpCourseManager:cpStopCourseRecorder()
    local spec = self.spec_cpCourseManager
    spec.courseRecorder:stop()
    local recordedCourse = spec.courseRecorder:getRecordedCourse()
    CpCourseManager.resetCourses(self)
    CpCourseManager.addCourse(self, recordedCourse)
end