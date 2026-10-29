package local.writingassistant.app.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ScrollToShowTest {
    @Test
    fun aVisibleChipKeepsThePosition() = assertEquals(50, scrollToShow(100..199, 50, 300))

    @Test
    fun aChipLeftOfTheViewportScrollsToItsStart() = assertEquals(20, scrollToShow(20..99, 50, 300))

    @Test
    fun aChipRightOfTheViewportScrollsToItsEnd() = assertEquals(300, scrollToShow(500..599, 0, 300))
}
