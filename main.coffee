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

WALK_TICKS = (60 / 6)
MOVEMENT_RANGE = 3
CURSOR_MOVE_PX = 3

c = document.createElement 'canvas'
c.width = WIDTH
c.height = HEIGHT
document.body.appendChild c
ctx = c.getContext '2d'

warriorImg = new Image()
warriorImg.src = 'gfx/fighter.png'

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
  constructor: (@tx, @ty, @img) ->
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
    ctx.drawImage @img, @x, @y
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
        @cb()

  moveOneStepCloserToPiece: ->
    dx = @x - @targetPiece.x
    dy = @y - @targetPiece.y
    dx = clamp dx, CURSOR_MOVE_PX
    dy = clamp dy, CURSOR_MOVE_PX
    @x -= dx
    @y -= dy

  slideOverPiece: (@targetPiece, @cb) ->
    if @isOverTargetPiece()
      @cb()

class CostMap
  costAt: (x, y) -> 1

class Radius extends Entity
  constructor: (@tx, @ty, @radius) ->
    super
    @zIndex = RADIUS

  draw: (ctx) ->
    ctx.fillStyle = '#ddd'
    for tx in [@tx-@radius..@tx+@radius]
      for ty in [@ty-@radius..@ty+@radius]
        @fillTileAt tx, ty if @distanceTo(tx, ty) <= @radius

  distanceTo: (tx, ty) ->
    Math.abs(@tx - tx) + Math.abs(@ty - ty)

  fillTileAt: (tx, ty) ->
    ctx.fillRect tx * TILE_WIDTH, ty * TILE_HEIGHT, TILE_WIDTH, TILE_HEIGHT

class PieceMoveSession
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
    m = new GamePiece 0, 0, warriorImg
    m1 = new GamePiece 1, 1, warriorImg
    @team = [m, m1]
    @selectedIndex = 0
    @selected = @team[@selectedIndex]
    @selected.select()
    @startTurn 0, 0, m

  inputUpdated: (controller) ->
    if @movePiece
      @movePiece.handleInput controller

  nextSelectedIndex: -> (@selectedIndex + 1) % @team.length

  selectNext: ->
    @selected.deselect()
    x = @selected.x
    y = @selected.y
    @selectedIndex = @nextSelectedIndex()
    @selected = @team[@selectedIndex]
    @startTurn x, y, @selected

  startTurn: (x, y, piece) ->
    @cursor = new Cursor x, y
    @cursor.slideOverPiece piece, =>
      piece.select()
      @cursor.kill()
      @cursor = null
      @movePiece = new PieceMoveSession piece, =>
        @movePiece = null
        @selectNext()

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
