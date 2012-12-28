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

FPS = 60
WALK_TICKS = (FPS / 6)
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
    e.baseTick() for e in @entities
    @entities = (e for e in @entities when e.alive)

class KeyFocusStack
  constructor: ->
    @stack = []

  push: (entity, cb) ->
    @stack.push {entity, cb}

  inputUpdated: (controller) ->
    return if @stack.length == 0
    pair = @stack[@stack.length - 1]
    if pair.entity.inputUpdated controller
      console.log 'done with', pair.entity
      @stack.pop()
      pair.cb?()

es = new EntitySet
fs = new KeyFocusStack

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
    @subTickers = []
    es.add @

  contains: (x, y) ->
    between @x, x, @x + @width and
      between @y, y, @y + @height

  kill: ->
    @subTickers = []
    @alive = false

  addSubTicker: (st) ->
    @subTickers.push st

  baseTick: ->
    @subTickers = (s for s in @subTickers when not s.tick())
    @tick()

  tick: ->
  draw: (ctx) ->

class MenuButton extends Entity
  MAX_OFFSET = 30
  OFFSET_PPS = FPS / 5
  SLIDE_DURATION = 5

  constructor: ->
    super()
    @x = (320/2 - 16) / 2
    @y = 240 - 16
    @offset = 0
    @zIndex = CURSOR
    @slideOut = new PositionSlide @, {x:0, y:-30}, SLIDE_DURATION, =>
      @slideOut = null
    @addSubTicker @slideOut

  isMoving: -> @slideOut != null

  tick: ->

  draw: (ctx) ->
    ctx.fillStyle = 'red'
    ctx.fillRect @x, @y, 16, 16

txInPx = (tx, ty) -> {x: tx * TILE_WIDTH, y: ty * TILE_HEIGHT}
ptEquals = (p, q) -> p.x == q.x and p.y == q.y

class PositionSlide
  constructor: (@entity, @delta, @duration, @cb) ->
    @startPos = {x: @entity.x, y: @entity.y}
    @targetPos = {x: @entity.x + @delta.x, y: @entity.y + @delta.y}
    @elapsed = 0

  atTargetPos: ->
    ptEquals @targetPos, @entity

  tick: ->
    if @atTargetPos()
      @cb()
      return true
    @elapsed++
    @interpolatePosition()
    false

  interpolatePosition: ->
    ratio = @elapsed / @duration
    dx = @targetPos.x - @startPos.x
    dy = @targetPos.y - @startPos.y
    @entity.x = @startPos.x + dx * ratio
    @entity.y = @startPos.y + dy * ratio

class GamePiece extends Entity
  constructor: (@tx, @ty, @imgSet) ->
    super()
    @selected = false
    @zIndex = PIECE
    @posSlide = null
    @dir = 'down'
    @x = @tx * TILE_WIDTH
    @y = @ty * TILE_HEIGHT

  select: ->
    return if @selected
    @selected = true

  deselect: ->
    @dir = 'down'
    @selected = false
    @radius = null

  isMoving: -> @posSlide != null

  tick: ->

  draw: (ctx) ->
    ctx.drawImage @imgSet[@dir], @x, @y
    if @selected
      ctx.strokeStyle = 'black'
      ctx.strokeRect @x, @y, @width, @height

  setDirection: (@dir) ->

  moveBy: (delta, cb) ->
    throw "already moving" if @isMoving()
    dpx = {x: delta.x * TILE_WIDTH, y: delta.y * TILE_HEIGHT}
    @posSlide = new PositionSlide @, dpx, WALK_TICKS, =>
      @tx += delta.x
      @ty += delta.y
      cb()
      @posSlide = null
    @addSubTicker @posSlide

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
    super()
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

class MenuSession
  constructor: ->
    @mb = new MenuButton

  inputUpdated: (controller) ->
    return false if @mb.isMoving()
    if controller.action()
      @mb.kill()
      @mb = null
      return true
    false

class PieceMoveSession
  constructor: (@piece, @radius) ->
    @startTx = @piece.tx
    @startTy = @piece.ty
    @done = false
    @pieceMoving = false
    @menuDone = false

  inputUpdated: (controller) ->
    return false if @pieceMoving
    return true if @menuDone
    if controller.action()
      @menuSession = new MenuSession
      fs.push @menuSession, =>
        @menuSession = null
        @radius.kill()
        @menuDone = true

    delta = controller.delta()
    return unless delta
    @piece.setDirection controller.dir()
    {x:dx, y:dy} = delta
    if @radius.canMove[[@piece.tx + dx, @piece.ty + dy]]
      @pieceMoving = true
      @piece.moveBy delta, =>
        @pieceMoving = false
    false

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
    fs.push @
    @startTurn 0, 0, m

  inputUpdated: (controller) ->
    return false

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
      @movePiece = new PieceMoveSession piece, radius
      fs.push @movePiece, =>
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
  fs.inputUpdated c
  tm.draw ctx
  e.draw ctx for e in es.entities when e.zIndex == RADIUS
  e.draw ctx for e in es.entities when e.zIndex == PIECE
  e.draw ctx for e in es.entities when e.zIndex == CURSOR

id = setInterval gameLoop, (1000/FPS)

stop = -> clearInterval id

clear()

###
ctx.fillStyle = 'red'
ctx.fillRect 0, 0, 20, 20
console.log ctx
###
