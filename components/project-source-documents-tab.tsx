import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"

export function ProjectSourceDocumentsTab() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Исходные данные (RAG)</CardTitle>
        <CardDescription>Источники данных для Retrieval-Augmented Generation</CardDescription>
      </CardHeader>
      <CardContent>
        <p className="text-sm text-muted-foreground">Конфигурация исходных данных скоро будет доступна...</p>
      </CardContent>
    </Card>
  )
}
