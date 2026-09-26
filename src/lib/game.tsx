import { createContext, useContext } from 'react'
import type { Game } from './supabase'

// which game the dashboard is looking at. everything that reads or writes goes through this
export type GameState = { game: number; games: Game[]; current: Game | undefined; reloadGames: () => void }

export const GameContext = createContext<GameState>({ game: 0, games: [], current: undefined, reloadGames: () => {} })

export const useGame = () => useContext(GameContext)

const KEY = 'ac-game'

// remembered per browser, it's only a convenience
export function savedGame(): number | null {
  try {
    const v = Number(localStorage.getItem(KEY))
    return Number.isSafeInteger(v) && v > 0 ? v : null
  } catch {
    return null
  }
}

export function saveGame(id: number) {
  try {
    localStorage.setItem(KEY, String(id))
  } catch {
    // private mode, fine
  }
}
