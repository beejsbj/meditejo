package meditofoundation.medito

import android.content.Context
import meditofoundation.medito.pigeon.MeditoAppIconManager

// Kept for the generated Pigeon API; Meditejo currently has one primary icon.
class AppIconManagerImpl(@Suppress("UNUSED_PARAMETER") context: Context) : MeditoAppIconManager {
    override fun getAlternateIconName(callback: (Result<String?>) -> Unit) {
        callback(Result.success(null))
    }

    override fun setAlternateIconName(iconName: String?, callback: (Result<Unit>) -> Unit) {
        callback(if (iconName == null) Result.success(Unit)
            else Result.failure(UnsupportedOperationException("Only the primary Meditejo icon is available")))
    }
}
