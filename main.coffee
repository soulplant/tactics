WIDTH = 320
HEIGHT = 240
TILE_WIDTH = 16
TILE_HEIGHT = 16

VKEY_LEFT = 37
VKEY_UP = 38
VKEY_RIGHT = 39
VKEY_DOWN = 40

# z-index
RADIUS = 0
PIECE = 1
CURSOR = 2

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

class GamePiece extends Entity
  constructor: (@tx, @ty, @name) ->
    super()
    @recalcOnscreenPos()
    @age = 0
    @selected = false
    @zIndex = PIECE

  select: ->
    @selected = true
    @radius = new Radius @tx, @ty, MOVEMENT_RANGE

  deselect: ->
    @selected = false
    @radius?.kill()
    @radius = null

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

  moveBy: (pt) ->
    @tx += pt.x
    @ty += pt.y
    @recalcOnscreenPos()

  recalcOnscreenPos: ->
    @x = @tx * TILE_WIDTH
    @y = @ty * TILE_HEIGHT

  tick: ->
    @age++

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
    if !@isOverTargetPiece()
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

  handleInput: (event) ->
    return if @cursor.isMoving()
    delta = @eventToDir event
    return unless delta
    @selected.moveBy delta
    @selectNext()

  nextSelectedIndex: -> (@selectedIndex + 1) % @team.length

  selectNext: ->
    @selected.deselect()
    @selectedIndex = @nextSelectedIndex()
    @selected = @team[@selectedIndex]
    @cursor.moveToPiece @selected

  eventToDir: (event) ->
    switch event.keyCode
      when VKEY_LEFT then {x:-1, y:0}
      when VKEY_UP then {x:0, y:-1}
      when VKEY_RIGHT then {x:1, y:0}
      when VKEY_DOWN then {x:0, y:1}

g = new Game

document.addEventListener 'keydown', (e) ->
  g.handleInput e
, false

gameLoop = ->
  clear()
  es.tick()
  e.draw ctx for e in es.entities when e.zIndex == RADIUS
  e.draw ctx for e in es.entities when e.zIndex == PIECE
  e.draw ctx for e in es.entities when e.zIndex == CURSOR

id = setInterval gameLoop, (1000/60)

clear()

###
ctx.fillStyle = 'red'
ctx.fillRect 0, 0, 20, 20
console.log ctx
###
