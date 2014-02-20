bn = require './bn'
{bufeq_secure,ASP} = require './util'
{make_esc} = require 'iced-error'
konst = require './const'
C = konst.openpgp
K = konst.kb
{BaseKeyPair,BaseKey} = require './basekeypair'
{SRF,MRF} = require './rand'
{eme_pkcs1_encode,eme_pkcs1_decode} = require './pad'

#=================================================================

class Pub extends BaseKey

  @type : C.public_key_algorithms.ELGAMAL
  type : Pub.type

  #----------------

  # The serialization order of the parameters in the public key
  @ORDER : [ 'p', 'g', 'y' ]
  ORDER : Pub.ORDER

  #----------------

  constructor : ({@p, @g, @y}) ->

  #----------------

  @alloc : (raw) -> 
    BaseKey.alloc Pub, raw

  #----------------

  encrypt : (m, cb) ->
    {g,y,p} = @pub
    await SRF().random_zn p.subtract(bn.nbv(2)), defer k
    k = k.add(nb.BigInteger.ONE)
    c = [
      g.modPow(k, p),
      y.modPow(k, p).multiply(m).mod(p)
    ]
    cb c

#=================================================================

class Priv extends BaseKey

  #----------------

  # The serialization order of the parameters in the public key
  @ORDER : [ 'x' ]
  ORDER : Priv.ORDER

  #-------------------

  constructor : ({@x,@pub}) ->

  #-------------------

  serialize : () -> @x.to_mpi_buffer()
  @alloc : (raw, pub) -> BaseKey.alloc Priv, raw, { pub }

  #----------------

  decrypt : (c, cb) ->
    p = @pub.p
    ret = c[0].modPow(@x,p).modInverse(p).multiply(c[1]).mod(p)
    cb ret

#=================================================================

class Pair extends BaseKeyPair

  #--------------------

  @Pub : Pub
  Pub : Pub
  @Priv : Priv
  Priv : Priv

  #--------------------

  @type : C.public_key_algorithms.ELGAMAL
  type : Pair.type

  #--------------------
  
  constructor : ({ pub, priv }) -> super { pub, priv }
  can_sign : () -> false
  @parse : (pub_raw) -> 
    ret = BaseKeyPair.parse Pair, pub_raw
    return ret

  #----------------

  pad_and_encrypt : (data, cb) ->
    err = ret = null
    await eme_pkcs1_encode data, @pub.p.mpi_byte_length(), defer err, m
    unless err?
      await @pub.encrypt m, defer c
      c_mpis = (i.to_mpi_buffer() for i in c)
      ret = @export_output { c_mpis } 
    cb err, ret

  #----------------

  decrypt_and_unpad : (ciphertext, cb) ->
    err = ret = null
    await @priv.decrypt ciphertext.c(), defer m
    b = m.to_padded_octects @pub.p
    [err, ret] = eme_pkcs1_decode b
    cb err, ret

  #----------------

  @parse_output : (buf) -> (Output.parse buf)
  export_output : (args) -> new Output args

#=================================================================

class Output

  #----------------------

  constructor : ({@c_mpis, @c_bufs}) ->

  #----------------------
  
  @parse : (buf) ->
    c_mpis = for i in [0...2] 
      [err, ret, buf, n] = bn.mpi_from_buffer buf
      throw err if err?
      ret
    throw new Error "junk at the end of input" unless buf.length is 0
    new Output { c_mpis }

  #----------------------
  
  c : () -> @c_mpis

  #----------------------
  
  get_c_bufs : () ->
    if @c_bufs? then @c_bufs
    else (@c_bufs = (i.to_mpi_buffer() for i in @c_mpis))

  #----------------------
  
  output : () -> Buffer.concat @get_c_bufs()

#=======================================================================

exports.ElGamal = exports.Pair = Pair

#=================================================================

