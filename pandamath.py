import math

def price_to_tick(p):
    return math.floor(math.log(p,1.0001))

q96=2**96

def price_to_sqrtp(p):
    return int(math.sqrt(p)*q96)

sqrtp_low=price_to_sqrtp(4545)
sqrtp_cur=price_to_sqrtp(5000)
sqrtp_upp=price_to_sqrtp(5500)

print(sqrtp_cur)

def liquidity0(amount,pa,pb):
    if pa>pb:
        pa,pb=pb,pa
    return (amount*(pa*pb)/q96)/(pb-pa)

def liquidity1(amount,pa,pb):
    if pa>pb:
        pa,pb=pb,pa
    return amount*q96/(pb-pa)

eth=10**18
amount_eth=1*eth
amount_usdc=5000*eth

liq0=liquidity0(amount_eth,sqrtp_cur,sqrtp_upp)
liq1=liquidity1(amount_usdc,sqrtp_cur,sqrtp_low)
liq=int(min(liq0,liq1))

print(liq)

def cal_amount0(liq,pa,pb):
    if pa>pb:
        pa,pb=pb,pa
    return int(liq*q96*(pb-pa)/pa/pb)

def cal_amount1(liq,pa,pb):
    if pa>pb:
        pa,pb=pb,pa
    return int(liq*(pb-pa)/q96)

amount0=cal_amount0(liq,sqrtp_upp,sqrtp_cur)
amount1=cal_amount1(liq,sqrtp_low,sqrtp_cur)

print(amount0,amount1)

max_tick=price_to_tick(2**128)

#Swap USDC for ETH
amount_in=42*eth
price_diff=(amount_in*q96)//liq
price_next=sqrtp_cur+price_diff
print('New price:',(price_next/q96)**2)
print('New sqrtP:',price_next)
print('New tick:',price_to_tick((price_next/q96)**2))

amount_in=cal_amount1(liq,price_next,sqrtp_cur)
amount_out=cal_amount0(liq,price_next,sqrtp_cur)
print('USDC in:', amount_in/eth)
print('ETH out:',amount_out/eth)

#Swap ETH for USDC
amount_in=0.01337*eth
print(f"\nSelling {amount_in/eth} ETH")

price_next=int((liq*sqrtp_cur*q96)//(liq*q96+amount_in*sqrtp_cur))

print("New price",(price_next/q96)**2)
print("New sqrtP:", price_next)
print("New tick:", price_to_tick((price_next/q96)**2))

amount_in=cal_amount0(liq, price_next,sqrtp_cur)
amount_out=cal_amount1(liq,price_next,sqrtp_cur)

print("ETH in",amount_in/eth)
print("USDC out", amount_out/eth)

tick=85176
word_pos= tick>>8 # or tick //2**8
bit_pos = tick%256
print(f"Word{word_pos}, bit {bit_pos}")

bit_pos=8
mask=2**bit_pos # or 1<< bit_pos
print(bin(mask))
word=(2**256)-1 #set word to all ones
print(bin(word))
print(bin(word^mask))


