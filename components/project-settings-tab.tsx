import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"

export function ProjectSettingsTab() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Настройки проекта</CardTitle>
        <CardDescription>Настройка параметров проекта и разрешений</CardDescription>
      </CardHeader>
      <CardContent>
        <p className="text-sm text-muted-foreground">Панель настроек скоро будет доступна...</p>
      </CardContent>
    </Card>
  )
}
