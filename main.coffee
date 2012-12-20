WIDTH = 320
HEIGHT = 240
TILE_WIDTH = 16
TILE_HEIGHT = 16

VKEY_LEFT = 37
VKEY_UP = 38
VKEY_RIGHT = 39
VKEY_DOWN = 40
VKEY_ENTER = 13

# z-index
RADIUS = 0
PIECE = 1
CURSOR = 2

WALK_TICKS = (60 / 4)
MOVEMENT_RANGE = 3

c = document.createElement 'canvas'
c.width = WIDTH
c.height = HEIGHT
document.body.appendChild c
ctx = c.getContext '2d'

clear = ->
  ctx.clearRect 0, 0, WIDTH, HEIGHT

class EntitySet
  constructor: ->
    @nextId = 0
    @entities = []

  add: (e) ->
    e.id = @nextId++
    @entities.push e

  tick: ->
    e.tick() for e in @entities
    @entities = (e for e in @entities when e.alive)

es = new EntitySet

between: (l, x, h) -> l <= x <= h

rectContains: (p1, rect) ->
  between rect.x, p1.x, rect.x + rect.width and
    between rect.y, p1.y, rect.y + rect.height

class Entity
  constructor: ->
    @x = @y = 0
    @width = TILE_WIDTH
    @height = TILE_HEIGHT
    @alive = true
    es.add @

  contains: (x, y) ->
    between @x, x, @x + @width and
      between @y, y, @y + @height

  kill: -> @alive = false

  tick: ->
  draw: (ctx) ->

txInPx = (tx, ty) -> {x: tx * TILE_WIDTH, y: ty * TILE_HEIGHT}

class GamePiece extends Entity
  constructor: (@tx, @ty, @name) ->
    super()
    @selected = false
    @zIndex = PIECE
    @ticksSinceWalkStart = -1
    @recalcOnscreenPos()

  select: ->
    return if @selected
    @selected = true
    @radius = new Radius @tx, @ty, MOVEMENT_RANGE

  deselect: ->
    @selected = false
    @radius?.kill()
    @radius = null

  isMoving: -> @ticksSinceWalkStart != -1

  tick: ->
    if @isMoving()
      @ticksSinceWalkStart = Math.min @ticksSinceWalkStart+1, WALK_TICKS
      if @ticksSinceWalkStart == WALK_TICKS
        # end of walk
        @tx = @targetTx
        @ty = @targetTy
        @ticksSinceWalkStart = -1
        @targetTx = undefined
        @targetTy = undefined
        @postWalkCb?()
        @postWalkCb = null
      @recalcOnscreenPos()

  draw: (ctx) ->
    ###
    ctx.fillStyle = 'red'
    ctx.fillRect @x, @y, @width, @height
    ###
    ctx.fillStyle = @name
    ctx.fillRect @x, @y, @width, @height
    if @selected
      ctx.strokeStyle = 'black'
      ctx.strokeRect @x, @y, @width, @height

  moveBy: (pt, cb) ->
    @targetTx = @tx + pt.x
    @targetTy = @ty + pt.y
    @ticksSinceWalkStart = 0
    @postWalkCb = cb
    @recalcOnscreenPos()

  recalcOnscreenPos: ->
    p = txInPx @tx, @ty
    if @isMoving()
      n = txInPx @targetTx, @targetTy
      walkCompletePercent = @ticksSinceWalkStart / WALK_TICKS
      dx = n.x - p.x
      dy = n.y - p.y
      p.x += dx * walkCompletePercent
      p.y += dy * walkCompletePercent
    @x = p.x
    @y = p.y

signum = (x) ->
  if x < 0
    -1
  else if x == 0
    0
  else
    1

clamp = (x, max_mag) ->
  signum(x) * Math.min(Math.abs(x), max_mag)

class Cursor extends Entity
  MAX_DELTA_PX = 2

  constructor: (x, y) ->
    super()
    @x = x
    @y = y
    @zIndex = CURSOR

  draw: (ctx) ->
    ctx.strokeStyle = 'black'
    ctx.strokeRect @x, @y, TILE_WIDTH, TILE_HEIGHT

  isOverTargetPiece: ->
    return false unless @targetPiece
    return @targetPiece.x == @x and @targetPiece.y == @y

  isMoving: ->
    not @isOverTargetPiece()

  tick: ->
    unless @isOverTargetPiece()
      @moveOneStepCloserToPiece()
      if @isOverTargetPiece()
        @targetPiece.select()

  moveOneStepCloserToPiece: ->
    dx = @x - @targetPiece.x
    dy = @y - @targetPiece.y
    dx = clamp dx, MAX_DELTA_PX
    dy = clamp dy, MAX_DELTA_PX
    @x -= dx
    @y -= dy

  moveToPiece: (@targetPiece) ->

class CostMap
  costAt: (x, y) -> 1

class Radius extends Entity
  constructor: (@tx, @ty, @radius) ->
    super
    @zIndex = RADIUS

  draw: (ctx) ->
    ctx.fillStyle = 'grey'
    for tx in [@tx-@radius..@tx+@radius]
      for ty in [@ty-@radius..@ty+@radius]
        @fillTileAt tx, ty if @distanceTo(tx, ty) <= @radius

  distanceTo: (tx, ty) ->
    Math.abs(@tx - tx) + Math.abs(@ty - ty)

  fillTileAt: (tx, ty) ->
    ctx.fillRect tx * TILE_WIDTH, ty * TILE_HEIGHT, TILE_WIDTH, TILE_HEIGHT

class MoveSession
  constructor: (@piece, @cb) ->
    @startTx = @piece.tx
    @startTy = @piece.ty
    @radius = new Radius @startTx, @startTy, MOVEMENT_RANGE
    @done = false
    @pieceMoving = false

  handleInput: (controller) ->
    return if @pieceMoving
    if controller.action()
      @radius.kill()
      @cb()

    delta = controller.delta()
    return unless delta
    return unless @canMoveTo delta
    @pieceMoving = true
    @piece.moveBy delta, =>
      @pieceMoving = false

  canMoveTo: (delta) ->
    x = @piece.tx + delta.x
    y = @piece.ty + delta.y
    Math.abs(@startTx - x) + Math.abs(@startTy - y) <= MOVEMENT_RANGE

isActionEvent = (event) ->
  switch event.keyCode
    when VKEY_ENTER then 'action'

eventToDir = (event) ->
  switch event.keyCode
    when VKEY_LEFT then {x:-1, y:0}
    when VKEY_UP then {x:0, y:-1}
    when VKEY_RIGHT then {x:1, y:0}
    when VKEY_DOWN then {x:0, y:1}

class Game
  constructor: ->
    m = new GamePiece 0, 0, 'red'
    m1 = new GamePiece 1, 1, 'green'
    @cursor = new Cursor 0, 0
    @cursor.moveToPiece m
    @team = [m, m1]
    @selectedIndex = 0
    @selected = @team[@selectedIndex]
    @selected.select()

  inputUpdated: (controller) ->
    return if @cursor.isMoving() or @selected.isMoving()
    if !@moveSession
      @moveSession = new MoveSession @selected, =>
        @moveSession = null
        @selectNext()
    @moveSession.handleInput controller

  nextSelectedIndex: -> (@selectedIndex + 1) % @team.length

  selectNext: ->
    @selected.deselect()
    @selectedIndex = @nextSelectedIndex()
    @selected = @team[@selectedIndex]
    @cursor.moveToPiece @selected

class Controller
  constructor: ->
    @keysDown = {}

  handleKeyDown: (event) ->
    @keysDown[event.keyCode] = true

  handleKeyUp: (event) ->
    @keysDown[event.keyCode] = false

  action: -> @keysDown[VKEY_ENTER]
  delta: ->
    return {x:-1, y:0} if @keysDown[VKEY_LEFT]
    return {x:0, y:-1} if @keysDown[VKEY_UP]
    return {x:1, y:0} if @keysDown[VKEY_RIGHT]
    return {x:0, y:1} if @keysDown[VKEY_DOWN]


c = new Controller
g = new Game

document.addEventListener 'keydown', (e) ->
  c.handleKeyDown e
, false

document.addEventListener 'keyup', (e) ->
  c.handleKeyUp e
, false

gameLoop = ->
  clear()
  es.tick()
  g.inputUpdated c
  e.draw ctx for e in es.entities when e.zIndex == RADIUS
  e.draw ctx for e in es.entities when e.zIndex == PIECE
  e.draw ctx for e in es.entities when e.zIndex == CURSOR

id = setInterval gameLoop, (1000/60)

stop = -> clearInterval id

clear()

###
ctx.fillStyle = 'red'
ctx.fillRect 0, 0, 20, 20
console.log ctx
###
