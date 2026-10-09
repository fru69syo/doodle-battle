package com.fru69syo.doodle_battle.ar

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner

/**
 * Lifecycle for the ComposeView hosted in the Flutter platform view.
 *
 * MainActivity is a plain FlutterActivity (not a ComponentActivity), so the
 * view tree has no lifecycle/saved-state owners that Compose and SceneView
 * need. This owner mirrors the Activity lifecycle while the platform view is
 * alive and is destroyed together with the view.
 */
class ArViewLifecycleOwner : LifecycleOwner, SavedStateRegistryOwner, ViewModelStoreOwner {
    private val registry = LifecycleRegistry(this)
    private val savedState = SavedStateRegistryController.create(this)
    private val store = ViewModelStore()

    init {
        savedState.performAttach()
        savedState.performRestore(null)
        registry.currentState = Lifecycle.State.CREATED
    }

    override val lifecycle: Lifecycle get() = registry
    override val savedStateRegistry: SavedStateRegistry get() = savedState.savedStateRegistry
    override val viewModelStore: ViewModelStore get() = store

    fun moveTo(state: Lifecycle.State) {
        if (registry.currentState == Lifecycle.State.DESTROYED) return
        // Never go back to INITIALIZED; DESTROYED only through destroy().
        val target = if (state == Lifecycle.State.DESTROYED || state == Lifecycle.State.INITIALIZED) {
            Lifecycle.State.CREATED
        } else {
            state
        }
        registry.currentState = target
    }

    fun destroy() {
        if (registry.currentState == Lifecycle.State.DESTROYED) return
        registry.currentState = Lifecycle.State.DESTROYED
        store.clear()
    }
}
