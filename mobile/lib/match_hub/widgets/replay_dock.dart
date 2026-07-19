import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme.dart';
import '../palette.dart';

class ReplayControlDock extends StatelessWidget {
  final ReplayStateView state;
  final Future<void> Function(String action, {int? minute, double? speed})
  onControl;

  const ReplayControlDock({
    super.key,
    required this.state,
    required this.onControl,
  });

  @override
  Widget build(BuildContext context) {
    if (state.mode == 'showcase') return _showcaseDock(context);
    return Container(
      color: HubColors.stadiumLift,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('REPLAY', style: label(color: AppColors.gold, size: 9)),
              const Spacer(),
              Text(
                "${state.currentMinute}' / ${state.totalMinutes}' · ${state.speed}x",
                style: body(color: AppColors.mutInk, size: 11),
              ),
            ],
          ),
          Slider(
            value: state.currentMinute.toDouble().clamp(
              0,
              state.totalMinutes.toDouble(),
            ),
            min: 0,
            max: state.totalMinutes.toDouble().clamp(1, 150),
            activeColor: AppColors.gold,
            inactiveColor: AppColors.lineInk,
            onChanged: (v) => onControl('seek', minute: v.round()),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => onControl(state.paused ? 'play' : 'pause'),
                icon: Icon(
                  state.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: AppColors.cream,
                ),
              ),
              TextButton(
                onPressed: () => onControl('speed', speed: 1),
                child: Text(
                  '1x',
                  style: body(color: AppColors.cream, size: 12),
                ),
              ),
              TextButton(
                onPressed: () => onControl('speed', speed: 2),
                child: Text(
                  '2x',
                  style: body(color: AppColors.cream, size: 12),
                ),
              ),
              TextButton(
                onPressed: () => onControl('speed', speed: 4),
                child: Text(
                  '4x',
                  style: body(color: AppColors.cream, size: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _showcaseDock(BuildContext context) => Container(
    color: HubColors.stadiumLift,
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'VERIFIED TxLINE HISTORICAL REPLAY',
              style: label(color: StadiumColors.mint, size: 9),
            ),
            const Spacer(),
            Text(
              "${state.currentMinute}' / ${state.totalMinutes}'",
              style: body(color: AppColors.cream, size: 11),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: state.totalMinutes == 0
              ? 0
              : state.currentMinute / state.totalMinutes,
          minHeight: 3,
          color: AppColors.gold,
          backgroundColor: AppColors.lineInk,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                state.nextBeatMinute == null
                    ? 'Authoritative result reached'
                    : state.awaitingAction
                    ? "Ready for the ${state.nextBeatMinute}' checkpoint"
                    : "Streaming every verified frame to ${state.nextBeatMinute}'…",
                style: body(color: AppColors.mutInk, size: 11.5),
              ),
            ),
            const SizedBox(width: 8),
            if (state.nextBeatMinute != null)
              FilledButton(
                onPressed: state.awaitingAction
                    ? () => onControl('nextBeat')
                    : null,
                child: Text(
                  state.awaitingAction ? 'NEXT BEAT' : 'ADVANCING',
                  style: label(color: Colors.white, size: 9),
                ),
              )
            else
              TextButton(
                onPressed: () => onControl('reset'),
                child: Text(
                  'RESET',
                  style: label(color: AppColors.gold, size: 9),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
