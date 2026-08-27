export const readStoredTheme = (storageOwner, key, allowedThemes) => {
  try {
    const storage = storageOwner.localStorage;
    const theme = storage.getItem(key);
    return allowedThemes.has(theme) ? theme : null;
  } catch (_error) {
    return null;
  }
};

export const writeStoredTheme = (storageOwner, key, theme) => {
  try {
    const storage = storageOwner.localStorage;
    if (theme === "system") storage.removeItem(key);
    else storage.setItem(key, theme);
  } catch (_error) {
    // Theme selection still applies to the current document.
  }
};

export const readStoredBranchStates = (storageOwner, key) => {
  try {
    const storage = storageOwner.localStorage;
    const value = JSON.parse(storage.getItem(key) || "[]");
    if (!Array.isArray(value)) return [];

    return value
      .filter(entry =>
        Array.isArray(entry) &&
        typeof entry[0] === "string" &&
        entry[0].length <= 200 &&
        typeof entry[1] === "boolean"
      )
      .slice(-200);
  } catch (_error) {
    return [];
  }
};

export const writeStoredBranchStates = (storageOwner, key, states) => {
  try {
    const storage = storageOwner.localStorage;
    storage.setItem(key, JSON.stringify(Array.from(states).slice(-200)));
  } catch (_error) {
    // Disclosure state remains available for the current document.
  }
};

export const chartHeadline = (series, unit, formatter) => {
  const points = series.flatMap(item => Array.isArray(item.points) ? item.points : []);
  if (!points.length) return "No data";
  if (series.length > 1) return `${series.length} series`;
  return formatter(series[0].points.at(-1)[1], unit);
};

export const chartAriaLabel = title => `${title || "History"} history chart`;

export const graphOmissionLabel = (processCount, relationshipCount) => {
  const labels = [];

  if (processCount > 0) labels.push(`${processCount} processes`);
  if (relationshipCount > 0) labels.push(`${relationshipCount} relationships`);

  return labels.length > 0 ? `${labels.join(" · ")} omitted` : "";
};

const anchoredColumns = [0, -1, 1, -2, 2];

export const anchoredNodeOffset = index => ({
  x: anchoredColumns[index % anchoredColumns.length] * 148,
  y: 94 + Math.floor(index / 5) * 94
});

export const newNodePlacements = (edges, nodeIds, currentNodeIds) => {
  const known = new Set(currentNodeIds);
  const pending = new Set(nodeIds);
  const placements = [];

  while (pending.size > 0) {
    const wave = Array.from(pending).flatMap(nodeId => {
      const incoming = edges.find(edge => edge.data.target === nodeId);

      if (incoming) {
        return known.has(incoming.data.source)
          ? [{ nodeId, anchorId: incoming.data.source }]
          : [];
      }

      const outgoing = edges.find(edge =>
        edge.data.source === nodeId && known.has(edge.data.target)
      );

      return [{ nodeId, anchorId: outgoing?.data.target || null }];
    });

    const ready = wave.length > 0
      ? wave
      : [{ nodeId: pending.values().next().value, anchorId: null }];

    ready.forEach(placement => {
      placements.push(placement);
      pending.delete(placement.nodeId);
      known.add(placement.nodeId);
    });
  }

  const anchorCounts = new Map();

  return placements.map(placement => {
    const ordinal = anchorCounts.get(placement.anchorId) || 0;
    anchorCounts.set(placement.anchorId, ordinal + 1);

    return { ...placement, offset: anchoredNodeOffset(ordinal) };
  });
};

export const revisionDecision = (
  currentEpoch,
  currentRevision,
  nextEpoch,
  nextRevision
) => {
  const reset = nextEpoch !== currentEpoch;
  return { reset, accept: reset || nextRevision >= currentRevision };
};
