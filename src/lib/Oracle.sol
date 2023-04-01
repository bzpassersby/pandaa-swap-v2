//SPDX-License-Identifier:MIT
pragma solidity ^0.8.14;

library Oracle {
    struct Observation {
        uint32 timestamp;
        int56 tickCumulative;
        bool initialized;
    }

    function initialize(
        Observation[65535] storage self,
        uint32 time
    ) internal returns (uint16 cardinality, uint16 cardinalityNext) {
        self[0] = Observation({
            timestamp: time,
            tickCumulative: 0,
            initialized: true
        });
        cardinality = 1;
        cardinalityNext = 1;
    }

    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 timestamp,
        int24 tick,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        Observation memory last = self[index];
        if (last.timestamp == timestamp) return (index, cardinality);
        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }
        indexUpdated = (index + 1) % cardinalityUpdated;
        self[indexUpdated] = transform(last, timestamp, tick);
    }

    function transform(
        Observation memory last,
        uint32 timestamp,
        int24 tick
    ) internal pure returns (Observation memory) {
        uint56 delta = timestamp - last.timestamp;
        return
            Observation({
                timestamp: timestamp,
                tickCumulative: last.tickCumulative +
                    int56(tick) *
                    int56(delta),
                initialized: true
            });
    }

    function grow(
        Observation[65535] storage self,
        uint16 current,
        uint16 next
    ) internal returns (uint16) {
        if (next <= current) return current;
        for (uint16 i = current; i < next; i++) {
            self[i].timestamp = 1;
        }
        return next;
    }

    function observe(
        Observation[65535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        int24 tick,
        uint16 index,
        uint16 cardinality
    ) internal view returns (int56[] memory tickCumulatives) {
        tickCumulatives = new int56[](secondsAgos.length);
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            tickCumulatives[i] = observeSingle(
                self,
                time,
                secondsAgos[i],
                tick,
                index,
                cardinality
            );
        }
    }

    function observeSingle(
        Observation[65535] storage self,
        uint32 time,
        uint32 secondsAgo,
        int24 tick,
        uint16 index,
        uint16 cardinality
    ) internal view returns (int56 tickCumulative) {
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            if (last.timestamp != time) last = transform(last, time, tick);
            return last.tickCumulative;
        }
        uint32 target = time - secondsAgo;
        (
            Observation memory beforeOrAt,
            Observation memory atOrAfter
        ) = getSurroudingObservations(
                self,
                time,
                target,
                tick,
                index,
                cardinality
            );
        if (target == beforeOrAt.timestamp) {
            //we're at the left boundary of timespan
            return (beforeOrAt.tickCumulative);
        } else if (target == atOrAfter.timestamp) {
            //we're at the right boundary
            return (atOrAfter.tickCumulative);
        } else {
            //target is in the middle of timespan
            uint56 observationTimeDelta = atOrAfter.timestamp -
                beforeOrAt.timestamp;
            uint56 targetDelta = target - beforeOrAt.timestamp;
            return (beforeOrAt.tickCumulative +
                ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) /
                    int56(observationTimeDelta)) *
                int56(targetDelta));
        }
    }

    function getSurroudingObservations(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        int24 tick,
        uint16 index,
        uint16 cardinality
    )
        private
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        beforeOrAt = self[index];
        // if target is at or after the latest observation, we can early return
        if (lte(time, beforeOrAt.timestamp, target)) {
            if (beforeOrAt.timestamp == target) {
                return (beforeOrAt, atOrAfter);
            } else {
                return (beforeOrAt, transform(beforeOrAt, target, tick));
            }
        }
        // if target occurs before the latest observation, search through the old observations,
        // ensure that the target is chornologically at or after the oldest observation
        beforeOrAt = self[(index + 1) % cardinality];
        // if cardinality is not fully written, oldest observation is at index '0'
        if (!beforeOrAt.initialized) beforeOrAt = self[0];
        //enusre that target is at or after the oldest observation
        require(lte(time, beforeOrAt.timestamp, target), "OLD");
        //search within observations
        return binarySearch(self, time, target, index, cardinality);
    }

    function binarySearch(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        uint16 index,
        uint16 cardinality
    )
        private
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        uint256 l = (index + 1) % cardinality;
        uint256 r = l + cardinality - 1;
        uint256 i;
        while (true) {
            i = (l + r) / 2;
            beforeOrAt = self[i % cardinality];
            // We've landed on aan uinitialize tick, keep searching higher (more recently). This happens when current cardinality is not fully written
            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }
            atOrAfter = self[(i + 1) % cardinality];
            bool targetAtorAfterL = lte(time, beforeOrAt.timestamp, target);
            //check if we've found the answer
            if (targetAtorAfterL && lte(time, target, atOrAfter.timestamp))
                break;
            //if target timestamp is smaller than 'l' timestamp, search the lower half of the cardinality
            if (!targetAtorAfterL)
                r = i - 1;
                //if we are on the right tract, keep searching at the upper half of the cardinality
            else l = i + 1;
        }
    }

    /// compare two 32-bit timestamps
    /// @param time A timestamp truncated to 32bits, must be greater or equal to 'a' and 'b' to determine overflow
    /// @param a A timestamp to compare with b, must be smaller or equal to 'time'
    /// @param b A ttimestamp to compare with a, must be smaller or equal to 'time'

    function lte(uint32 time, uint32 a, uint32 b) private pure returns (bool) {
        // if there hasn't been overflow or all of the three params overflowed, 'a' and 'b' can be compared directly
        if (a <= time && b <= time) return a <= b;
        // if a>time, 'time' overflowed, if a<time, both 'a' and 'time' overflowed
        uint256 aAdjusted = a > time ? a : a + 2 ** 32;
        uint256 bAdjusted = b > time ? b : b + 2 ** 32;
        return aAdjusted <= bAdjusted;
    }
}
