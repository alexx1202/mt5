import math
import argparse


def calculate_oanda_position_size(price, digits, point, tick_value, tick_size,
                                   contract_size, balance, risk_mode, risk_pct,
                                   fixed_risk, sl_unit, sl_value, commission,
                                   volume_step, rr_ratio, min_net, side):
    pip_size = 10 ** (-digits + 1)
    pip_value = tick_value * pip_size / tick_size
    sl_pips = sl_value if sl_unit == "pips" else sl_value * point / pip_size

    if commission == 7:
        commission = 0

    risk_amount = fixed_risk if risk_mode == "aud" else balance * risk_pct / 100
    if risk_amount <= 0:
        raise ValueError("Risk amount must be positive")

    lot_raw = risk_amount / (sl_pips * pip_value + commission)
    lot = math.ceil(lot_raw / volume_step) * volume_step
    lot_precision = round(math.log10(1 / volume_step))
    lot = round(lot, lot_precision)

    commiss = lot * commission
    tp_pips = sl_pips * rr_ratio
    net_reward = tp_pips * pip_value * lot - commiss

    required_profit = max(risk_amount * rr_ratio, min_net)
    while net_reward < required_profit:
        tp_pips += 0.5
        net_reward = tp_pips * pip_value * lot - commiss

    buy = side.lower() == "buy"
    sl_price = price - sl_pips * pip_size if buy else price + sl_pips * pip_size
    tp_price = price + tp_pips * pip_size if buy else price - tp_pips * pip_size

    result = {
        "lot_size": round(lot, lot_precision),
        "commission": round(commiss, 2),
        "net_risk": round(sl_pips * pip_value * lot + commiss, 2),
        "stop_loss": sl_value,
        "take_profit": round(tp_pips * (pip_size / point) if sl_unit != "pips" else tp_pips, 1),
        "tp_price": tp_price,
        "sl_price": sl_price,
        "net_profit": round(net_reward, 2),
    }
    return result


def main():
    p = argparse.ArgumentParser(description="OANDA position size calculation")
    p.add_argument("price", type=float, help="Current price")
    p.add_argument("digits", type=int, help="Symbol digits")
    p.add_argument("point", type=float, help="Point size")
    p.add_argument("tick_value", type=float, help="Tick value")
    p.add_argument("tick_size", type=float, help="Tick size")
    p.add_argument("contract_size", type=float, help="Contract size")
    p.add_argument("balance", type=float, help="Account balance")
    p.add_argument("risk_mode", choices=["pct", "aud"], help="Risk mode")
    p.add_argument("risk_value", type=float, help="Risk percent or fixed amount")
    p.add_argument("sl_unit", choices=["pips", "points"], help="Stop loss unit")
    p.add_argument("sl_value", type=float, help="Stop loss value")
    p.add_argument("commission", type=float, default=7, nargs="?", help="Commission per lot")
    p.add_argument("volume_step", type=float, default=1, nargs="?", help="Volume step")
    p.add_argument("rr_ratio", type=float, default=2, nargs="?", help="Risk reward ratio")
    p.add_argument("min_net", type=float, default=20, nargs="?", help="Minimum net profit")
    p.add_argument("side", choices=["buy", "sell"], help="Trade side")

    args = p.parse_args()
    fixed_risk = args.risk_value if args.risk_mode == "aud" else 0
    risk_pct = args.risk_value if args.risk_mode == "pct" else 0

    res = calculate_oanda_position_size(
        price=args.price,
        digits=args.digits,
        point=args.point,
        tick_value=args.tick_value,
        tick_size=args.tick_size,
        contract_size=args.contract_size,
        balance=args.balance,
        risk_mode=args.risk_mode,
        risk_pct=risk_pct,
        fixed_risk=fixed_risk,
        sl_unit=args.sl_unit,
        sl_value=args.sl_value,
        commission=args.commission,
        volume_step=args.volume_step,
        rr_ratio=args.rr_ratio,
        min_net=args.min_net,
        side=args.side,
    )

    for k, v in res.items():
        print(f"{k.replace('_', ' ').title()}: {v}")


if __name__ == "__main__":
    main()
