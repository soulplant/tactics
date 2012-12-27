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

loadImage = (fn) ->
  img = new Image()
  img.src = fn
  img

warriorImgs = {}
warriorImgs['left'] = loadImage 'gfx/fighter-l.png'
warriorImgs['right'] = loadImage 'gfx/fighter-r.png'
warriorImgs['up'] = loadImage 'gfx/fighter-u.png'
warriorImgs['down'] = loadImage 'gfx/fighter-d.png'

tileImgs = {}
tileImgs['grass'] = loadImage 'gfx/grass.png'
tileImgs['dirt'] = loadImage 'gfx/dirt.png'

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
  constructor: (@tx, @ty, @imgSet) ->
    super()
    @selected = false
    @zIndex = PIECE
    @ticksSinceWalkStart = -1
    @recalcOnscreenPos()
    @dir = 'down'

  select: ->
    return if @selected
    @selected = true

  deselect: ->
    @dir = 'down'
    @selected = false
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
    ctx.drawImage @imgSet[@dir], @x, @y
    if @selected
      ctx.strokeStyle = 'black'
      ctx.strokeRect @x, @y, @width, @height

  setDirection: (@dir) ->

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
  MAX_MAP_WIDTH = 1024
  constructor: (@tx, @ty, @movePoints, @tileMap) ->
    if !@tileMap
      debugger
    super
    @zIndex = RADIUS
    @canMove = {}
    @populateMap @canMove, @tx, @ty, @movePoints, {}

  populateMap: (m, x, y, movePointsLeft, visited) ->
    return if movePointsLeft <= 0
    return if visited[[x, y]]
    m[[x, y]] = movePointsLeft
    visited[[x, y]] = true
    for [dy, dx] in [[0, -1], [0, 1], [1, 0], [-1, 0]]
      rx = x + dx
      ry = y + dy
      continue if visited[[rx, ry]]
      pl = movePointsLeft - @tileMap.costAt rx, ry
      @populateMap m, rx, ry, pl, visited


  draw: (ctx) ->
    ctx.fillStyle = 'rgba(30, 30, 30, 0.30)'
    for tx in [@tx-@movePoints..@tx+@movePoints]
      for ty in [@ty-@movePoints..@ty+@movePoints]
        if @canMove[[tx, ty]]
          @fillTileAt tx, ty

  distanceTo: (tx, ty) ->
    Math.abs(@tx - tx) + Math.abs(@ty - ty)

  fillTileAt: (tx, ty) ->
    ctx.fillRect tx * TILE_WIDTH, ty * TILE_HEIGHT, TILE_WIDTH, TILE_HEIGHT

class PieceMoveSession
  constructor: (@piece, @radius, @cb) ->
    @startTx = @piece.tx
    @startTy = @piece.ty
    @done = false
    @pieceMoving = false

  handleInput: (controller) ->
    return if @pieceMoving
    if controller.action()
      @radius.kill()
      @cb()

    delta = controller.delta()
    return unless delta
    @piece.setDirection controller.dir()
    {x:dx, y:dy} = delta
    if @radius.canMove[[@piece.tx + dx, @piece.ty + dy]]
      @pieceMoving = true
      @piece.moveBy delta, =>
        @pieceMoving = false

isActionEvent = (event) ->
  switch event.keyCode
    when VKEY_ENTER then 'action'

eventToDir = (event) ->
  switch event.keyCode
    when VKEY_LEFT then {x:-1, y:0}
    when VKEY_UP then {x:0, y:-1}
    when VKEY_RIGHT then {x:1, y:0}
    when VKEY_DOWN then {x:0, y:1}

class TileMap
  GRASS = 0
  DIRT = 1
  constructor: (@width, @height, @imgSet) ->
    @tiles = (x, y) -> if x < 5 then DIRT else GRASS
    @costs = [1, 2]
    @names = ['grass', 'dirt']

  draw: (ctx) ->
    for x in [0...@width]
      for y in [0...@height]
        xPx = x * TILE_WIDTH
        yPx = y * TILE_HEIGHT
        ctx.drawImage @imgSet[@names[@tiles(x, y)]], xPx, yPx

  costAt: (x, y) ->
    t = @costs[@tiles x, y]
    if t then t else 100

class Game
  constructor: (@tileMap) ->
    m = new GamePiece 1, 2, warriorImgs
    m1 = new GamePiece 8, 2, warriorImgs
    @team = [m, m1]
    @selectedIndex = 0
    @selected = @team[@selectedIndex]
    @selected.select()
    @movePiece = null
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

      radius = new Radius piece.tx, piece.ty, MOVEMENT_RANGE, @tileMap
      @movePiece = new PieceMoveSession piece, radius, =>
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
  dir: ->
    return 'left' if @keysDown[VKEY_LEFT]
    return 'right' if @keysDown[VKEY_RIGHT]
    return 'up' if @keysDown[VKEY_UP]
    return 'down' if @keysDown[VKEY_DOWN]
  delta: ->
    return {x:-1, y:0} if @keysDown[VKEY_LEFT]
    return {x:0, y:-1} if @keysDown[VKEY_UP]
    return {x:1, y:0} if @keysDown[VKEY_RIGHT]
    return {x:0, y:1} if @keysDown[VKEY_DOWN]


tm = new TileMap 10, 10, tileImgs
c = new Controller
g = new Game tm

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
  tm.draw ctx
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
